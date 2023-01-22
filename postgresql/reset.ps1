psql -f $PSScriptRoot\clear.sql -U postgres
psql -f $PSScriptRoot\create.sql -U postgres
psql -f $PSScriptRoot\fill_test.sql -U postgres