psql -f $PSScriptRoot\clear.sql -U postgres
psql -f $PSScriptRoot\create.sql -U postgres
psql -f $PSScriptRoot\fill.sql -U postgres