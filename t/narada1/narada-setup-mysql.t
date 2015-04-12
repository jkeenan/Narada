use t::narada1::share; guard my $guard;
use DBI;
use Narada::Config qw( set_config );

require (wd().'/blib/script/narada-setup-mysql');


my ($db, $login, $pass) = path(wd().'/t/.answers')->lines_utf8({ count => 3, chomp => 1 });
plan skip_all => 'No database provided for testing' if $db eq q{};
my $lock = path(wd().'/t/.answers')->filehandle({locked=>1}, '>>');


$::dbh = DBI->connect('dbi:mysql:', $login, $pass, {RaiseError=>1});
BAIL_OUT 'Database already exists' if db_exists();


# - main()
#   * too many params
#   * wrong params
#   * no config/db/db: do nothing
#   * bad pass
#   * --clean: make sure database dropped, if exists
#   * throw on non-empty database
#   * without SCHEME: make sure database created, if not exists
#   * with SCHEME: make sure SCHEME imported
#   * with SCHEME and several .sql: make sure all imported

throws_ok { main('param-1', 'param-2') }    qr/Usage:/,
    'main: too many params';

throws_ok { main('not_existing_param') }    qr/Usage:/,
    'main: wrong param';

main();
is db_exists(), 0,
    'main: do nothing without config/db/db';

set_config('db/db', $db);
set_config('db/login', $login);
set_config('db/pass', 'wrong pass');
throws_ok { main() }    qr/Access denied/i,
    'main: bad pass';
set_config('db/pass', $pass);

main('--clean');
is db_exists(), 0,
    'main: --clean without database';
$::dbh->do('CREATE DATABASE '.$db);
is db_exists(), 1,
    'main: db created';
main('--clean');
is db_exists(), 0,
    'main: --clean dropped database';

$::dbh->do('CREATE DATABASE '.$db);
$::dbh->do('USE '.$db);
$::dbh->do('CREATE TABLE a (i int)');
throws_ok { main() }    qr/database does not empty/,
    'main: database does not empty';
$::dbh->do('DROP DATABASE '.$db);

is db_exists(), 0,
    'main: db not exists';
main();
is db_exists(), 1,
    'main: database created (not exists)';
main();
is db_exists(), 1,
    'main: database created (exists)';

Echo('var/sql/db.scheme.sql',"CREATE TABLE a (i int);\nCREATE TABLE b (j int);\n");
is_deeply list_tables(), {},
    'main: no tables';
output_from { main() };
is_deeply list_tables(), {a => 0, b => 0},
    'main: scheme loaded';
main('--clean');

Echo('var/sql/a.sql',"INSERT INTO a VALUES (10), (20);\n");
Echo('var/sql/b.sql',"INSERT INTO b VALUES (10), (20), (30);\n");
is_deeply list_tables(), {},
    'main: no tables';
output_from { main() };
is_deeply list_tables(), {a => 2, b => 3},
    'main: scheme and table dumps loaded';
main('--clean');

# - import_sql()
#   * throw if file unreadable
#   * throw if file contain wrong SQL

$::dbh->do('CREATE DATABASE IF NOT EXISTS '.$db);

chmod 0, 'var/sql/a.sql' or die "chmod: $!";
throws_ok { output_from { import_sql('var/mysql/a.sql') } }   qr/failed to import/i,
    'import_sql: file unreadable';
chmod 0644, 'var/sql/a.sql' or die "chmod: $!";

Echo('var/sql/c.sql', 'some junk here');
throws_ok { output_from { import_sql('var/mysql/c.sql') } }   qr/failed to import/i,
    'import_sql: file contain wrong SQL';


$::dbh->do('DROP DATABASE IF EXISTS '.$db);
done_testing();


sub Echo {
    my ($filename, $content) = @_;
    open my $fh, '>', $filename                         or die "open: $!";
    print {$fh} $content;
    close $fh                                           or die "close: $!";
    return;
}

sub db_exists {
    return 0+$::dbh->prepare('SHOW DATABASES LIKE ?')->execute($db);
}

sub list_tables {
    return {} if !db_exists();
    my %tables;
    for my $t (@{ $::dbh->selectcol_arrayref('SHOW TABLES') }) {
        $tables{$t} = $::dbh->selectcol_arrayref('SELECT COUNT(*) FROM '.$t)->[0];
    }
    return \%tables;
}
