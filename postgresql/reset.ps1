param (
    $user = "postgres",
    $pg_host = "localhost",
    $port = "5432",
    $dbname = "postgres",
    $schema = "flash_cards_repeat_system",
    $pg_password = $env:PGPASSWORD
)

if ($null -eq $pg_password) {
    Write-Host "PGPASSWORD isn't set up"
    Write-Host 'please, set $env:PGPASSWORD="your postgres password"'
} else {
    psql -f $PSScriptRoot\create.sql -U $user "dbname=$dbname host=$pg_host port=$port options=--search_path=$schema"
    psql -f $PSScriptRoot\fill_test.sql  -U $user "dbname=$dbname host=$pg_host port=$port options=--search_path=$schema"

    Write-Host
    Write-Host "config:"
    Write-Host "    user = $user"
    Write-Host "    host = $pg_host"
    Write-Host "    port = $port"
    Write-Host "    dbname = $dbname"
    Write-Host "    schema = $schema"
    Write-Host "    off_fill = $off_fill"
    Write-Host "tip:"
    Write-Host "    you can configure variables like -<variable_name> value"
    Write-Host "    example:"
    Write-Host "        -server_port 2222"
}