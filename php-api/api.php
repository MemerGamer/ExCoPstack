<?php
declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;

date_default_timezone_set('UTC');

// Get configuration from environment variables (set via ConfigMap/Secret)
$storageDir = getenv('EXCEL_STORAGE_PATH') ?: __DIR__ . '/storage';
$xlsx = $storageDir . '/wanted.xlsx';
$sheetName = getenv('EXCEL_SHEET_NAME') ?: 'Wanted';

@mkdir($storageDir, 0777, true);

function loadSheet(string $path, string $sheetName) {
    if (!file_exists($path)) {
        $spreadsheet = new Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle($sheetName);
        $sheet->fromArray([['id','name','bounty','updated_at']], null, 'A1');
        IOFactory::createWriter($spreadsheet, 'Xlsx')->save($path);
    }
    $reader = IOFactory::createReader('Xlsx');
    $spreadsheet = $reader->load($path);
    $sheet = $spreadsheet->getSheetByName($sheetName)
        ?? $spreadsheet->getActiveSheet();
    return [$spreadsheet, $sheet];
}

function saveSheet($spreadsheet, string $path): void {
    $writer = IOFactory::createWriter($spreadsheet, 'Xlsx');
    $writer->save($path);
}

function csv_escape(array $row): string {
    $escaped = array_map(function($v){
        $v = (string)$v;
        if (strpbrk($v, ",\"\n\r") !== false) {
            $v = '"' . str_replace('"', '""', $v) . '"';
        }
        return $v;
    }, $row);
    return implode(',', $escaped) . "\n";
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

// CORS headers to allow requests from COBOL frontend
// In Kubernetes, requests come through Ingress, so we allow all origins
// In production, you'd restrict this to specific domains
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin) {
    header('Access-Control-Allow-Origin: ' . $origin);
    header('Access-Control-Allow-Credentials: true');
} else {
    // Allow all origins for Kubernetes/Ingress scenarios
    header('Access-Control-Allow-Origin: *');
}
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// Handle preflight OPTIONS request
if ($method === 'OPTIONS') {
    http_response_code(200);
    exit;
}

header('Content-Type: text/plain; charset=utf-8');

if ($method === 'GET' && $path === '/api/wanted') {
    [$spreadsheet, $sheet] = loadSheet($xlsx, $sheetName);

    $lock = fopen($xlsx . '.lock', 'c');
    if ($lock) { flock($lock, LOCK_SH); }

    $highestRow = $sheet->getHighestDataRow();
    for ($r = 2; $r <= $highestRow; $r++) {
        $id = (string)$sheet->getCell('A'.$r)->getValue();
        $name = (string)$sheet->getCell('B'.$r)->getValue();
        $bounty = (string)$sheet->getCell('C'.$r)->getValue();
        $updated = (string)$sheet->getCell('D'.$r)->getValue();
        echo csv_escape([$id, $name, $bounty, $updated]);
    }

    if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    exit;
}

if ($method === 'POST' && $path === '/api/wanted') {
    [$spreadsheet, $sheet] = loadSheet($xlsx, $sheetName);

    $lock = fopen($xlsx . '.lock', 'c');
    if ($lock) { flock($lock, LOCK_EX); }

    $highestRow = $sheet->getHighestDataRow();
    $existing = max(0, $highestRow - 1);
    $id = (string)($existing + 1);

    $name = trim($_POST['name'] ?? '');
    $bounty = trim($_POST['bounty'] ?? '');

    if ($name === '' || $bounty === '') {
        http_response_code(400);
        echo "error,missing-name-or-bounty\n";
        if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
        exit;
    }

    $updated = (new DateTimeImmutable('now'))->format('c');

    $sheet->fromArray([[$id, $name, $bounty, $updated]], null, 'A' . ($highestRow + 1));
    saveSheet($spreadsheet, $xlsx);

    if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    
    // Redirect back to COBOL frontend
    // Use Referer header if available (from Ingress), otherwise use environment variable or relative path
    $referer = $_SERVER['HTTP_REFERER'] ?? '';
    if ($referer) {
        // Extract the base URL from referer (remove any path after domain)
        $parsed = parse_url($referer);
        $frontendUrl = ($parsed['scheme'] ?? 'http') . '://' . ($parsed['host'] ?? '') . '/';
    } else {
        $frontendUrl = getenv('FRONTEND_URL') ?: '/';
    }
    header('Location: ' . $frontendUrl);
    http_response_code(303);
    exit;
}

if ($method === 'PUT' && preg_match('#^/api/wanted/(\d+)$#', $path, $matches)) {
    $id = $matches[1];
    [$spreadsheet, $sheet] = loadSheet($xlsx, $sheetName);

    $lock = fopen($xlsx . '.lock', 'c');
    if ($lock) { flock($lock, LOCK_EX); }

    $highestRow = $sheet->getHighestDataRow();
    $found = false;
    
    for ($r = 2; $r <= $highestRow; $r++) {
        $rowId = (string)$sheet->getCell('A'.$r)->getValue();
        if ($rowId === $id) {
            parse_str(file_get_contents('php://input'), $_PUT);
            $name = trim($_PUT['name'] ?? '');
            $bounty = trim($_PUT['bounty'] ?? '');
            
            if ($name === '' || $bounty === '') {
                http_response_code(400);
                echo "error,missing-name-or-bounty\n";
                if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
                exit;
            }
            
            $updated = (new DateTimeImmutable('now'))->format('c');
            $sheet->setCellValue('B'.$r, $name);
            $sheet->setCellValue('C'.$r, $bounty);
            $sheet->setCellValue('D'.$r, $updated);
            saveSheet($spreadsheet, $xlsx);
            $found = true;
            break;
        }
    }
    
    if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    
    if (!$found) {
        http_response_code(404);
        echo "error,not-found\n";
        exit;
    }
    
    http_response_code(200);
    echo "ok\n";
    exit;
}

if ($method === 'DELETE' && preg_match('#^/api/wanted/(\d+)$#', $path, $matches)) {
    $id = $matches[1];
    [$spreadsheet, $sheet] = loadSheet($xlsx, $sheetName);

    $lock = fopen($xlsx . '.lock', 'c');
    if ($lock) { flock($lock, LOCK_EX); }

    $highestRow = $sheet->getHighestDataRow();
    $found = false;
    
    for ($r = 2; $r <= $highestRow; $r++) {
        $rowId = (string)$sheet->getCell('A'.$r)->getValue();
        if ($rowId === $id) {
            $sheet->removeRow($r);
            saveSheet($spreadsheet, $xlsx);
            $found = true;
            break;
        }
    }
    
    if ($lock) { flock($lock, LOCK_UN); fclose($lock); }
    
    if (!$found) {
        http_response_code(404);
        echo "error,not-found\n";
        exit;
    }
    
    http_response_code(200);
    echo "ok\n";
    exit;
}

http_response_code(404);
echo "notfound\n";