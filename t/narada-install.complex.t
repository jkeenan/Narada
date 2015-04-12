use t::share; guard my $guard;

require (wd().'/blib/script/narada-install');


sub is_version;
sub is_backups;
my ($narada_bin) = grep {-x "$_/narada-new"} split /:/, $ENV{PATH};
my $tmp_bin = tempdir('narada.bin.XXXXXX');
$ENV{PATH} = "$tmp_bin:$ENV{PATH}";
my @answers;
my $module = Test::MockModule->new('main');
$module->mock(ask => sub {
    if (@answers) {
        return shift @answers;
    }
    else {
        local *STDOUT = *STDERR;
        $module->original('ask')->(@_);
    }
});


# - complex functional test:
before($tmp_bin, 'narada-backup',  'test -f .release/fail-backup-$(cat VERSION) && exit 1');
before($tmp_bin, 'narada-restore', 'test -f .release/fail-$(basename "$1" .tar) && exit 1');
setup('1.5.0');
is_version '1.5.0';
is_backups [qw( full-1.1.0 full-1.2.0 full-1.3.0 full-1.4.0 )];
#       1.5.0 downgrade to 1.4.0,
#       1.4.0 downgrade to 1.3.0,
#       1.3.0 restore to   1.2.0,
#       1.2.0 downgrade to 1.1.0,
#       1.1.0 downgrade to 0.0.0,
#       0.0.0 upgrade to   2.1.0,
#       2.1.0 upgrade to   2.2.0,
#       2.2.0 upgrade to   2.3.0.
#   * check is all backups was created
path('.backup/full-1.2.0.tar')->move('tmp/full-1.2.0.tar');
$_->remove for path('.backup')->children;
throws_ok { output_from { main(qw( -R 2.3.0 )) } } qr/backup not found/;
path('tmp/full-1.2.0.tar')->move('.backup/full-1.2.0.tar');
output_from { main(qw( -R 2.3.0 )) };
is_version '2.3.0';
is_backups [qw( full-1.1.0 full-1.2.0 full-1.3.0 full-1.4.0 full-1.5.0 full-2.1.0 full-2.2.0 )];
#   * test error while first backup
$_->remove for path('.backup')->children;
@answers = qw( restore continue );
path('.release/fail-backup-2.3.0')->touch;
ok !path('.lock.new')->exists, 'no .lock.new';
throws_ok { output_from { main(qw( -D 0.0.0 )) } } qr/Migration failed/i, 'error while first backup: restore';
ok path('.lock.new')->exists, '.lock.new was left after failed migration';
is_backups [];
is_version '2.3.0';
lives_ok  { output_from { main(qw( -D 0.0.0 )) } } 'error while first backup: continue';
ok !path('.lock.new')->exists, 'no .lock.new';
is_backups [qw( full-2.1.0 full-2.2.0 )];
is_version '0.0.0';
path('.release/fail-backup-2.3.0')->remove;
#   * test error while middle backup
setup('2.3.0');
@answers = qw( restore continue );
path('.release/fail-backup-1.3.0')->touch;
throws_ok { output_from { main(qw( -D 1.5.0 )) } } qr/Migration failed/i, 'error while middle backup: restore';
is_backups [qw( full-1.1.0 full-1.2.0 full-2.1.0 full-2.2.0 full-2.3.0 )];
is_version '1.2.0';
$_->remove for path('.backup')->children;
lives_ok  { output_from { main(qw( 1.5.0    )) } } 'error while middle backup: continue';
is_backups [qw( full-1.2.0 full-1.4.0 )];
is_version '1.5.0';
path('.release/fail-backup-1.3.0')->remove;
#   * test error while middle downgrade
@answers = qw( restore continue );
path('.release/fail-downgrade-1.2.0')->touch;
throws_ok { output_from { main(qw( -R 0.0.0 )) } } qr/Migration failed/i, 'error while middle downgrade: restore';
ok !path('.backup/full.tar')->exists, 'no full.tar'; # this may be wrong: $Last_backup optimization doesn't finished on error
is_version '1.2.0';
lives_ok  { output_from { main(qw( -f .release/1.5.0.migrate -D 0.0.0 )) } } 'error while middle downgrade: continue';
is_version '0.0.0';
path('.release/fail-downgrade-1.2.0')->remove;
#   * test error while middle upgrade
@answers = qw( restore continue );
path('.release/fail-upgrade-2.2.0')->touch;
throws_ok { output_from { main(qw( 2.3.0 )) } } qr/Migration failed/i, 'error while middle upgrade: restore';
is_version '2.1.0';
lives_ok  { output_from { main(qw( 2.3.0 )) } } 'error while middle upgrade: continue';
is_version '2.3.0';
path('.release/fail-upgrade-2.2.0')->remove;
#   * test error while restore
setup('1.5.0');
@answers = qw( restore );
path('.release/fail-full-1.2.0')->touch;
throws_ok { output_from { main(qw( -R 0.0.0 )) } } qr/Migration failed/i, 'error while restore: restore';
is_version '1.3.0';
path('.release/fail-full-1.2.0')->remove;
#   * test error while restore after error
setup('1.5.0');
@answers = qw( restore );
path('.release/fail-full-1.2.0')->touch;
path('.release/fail-full-1.3.0')->touch;
throws_ok { output_from { main(qw( -R 0.0.0 )) } } qr/Migration failed/i, 'error while restore after error';
is_version '1.3.0';
path('.release/fail-full-1.2.0')->remove;
path('.release/fail-full-1.3.0')->remove;


done_testing();


sub is_version {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if ($_[0] eq '0.0.0') {
        ok !path('VERSION')->exists, 'no VERSION';
    }
    elsif (path('VERSION')->exists) {
        my ($v) = path('VERSION')->lines({chomp=>1});
        is $v, $_[0], $_[1] // "version: $_[0]";
    }
    else {
        ok 0, $_[1] // "version: $_[0]";
    }
}

sub is_backups {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply [ sort map { $_->basename('.tar') }
        path('.backup')->children(qr/\A(?!full[.]tar\z|incr[.]tar\z|snap\z)/ms)
        ], $_[0], $_[1] // "backups: @{$_[0]}";
}

sub before {
    my ($tmp_bin, $file, $cmd) = @_;
    path("$tmp_bin/$file")->spew(<<"EOF");
#!/bin/sh
$cmd
exec $narada_bin/$file "\$@"
EOF
    path("$tmp_bin/$file")->chmod(0755);
}

sub setup {
    my ($v) = @_;
    output_from { main(qw( -f .release/1.5.0.migrate -f .release/2.3.0.migrate -R 0.0.0 )) };
    path('.backup')->remove_tree;
    output_from { main($v) };
}
