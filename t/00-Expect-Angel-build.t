use Test::Differences;    # qw(eq_or_diff);
use Test::Exception;      # qw(throws_ok)
use Test::More 'no_plan'; #tests => 2;
use File::Temp ();
require( 'lib/Expect/Angel.pm' );
#BEGIN { use_ok('Expect::Angel') };
our $class = 'Expect::Angel';

test_isa_what();
test_constructor_default_params();
test_constructor_params();
test_log();
test_initial_state();



sub test_isa_what {
    my $object = $class->build();
    isa_ok( $object, $class );
    return 0;
}

sub test_constructor_default_params {
    my $object = $class->build();
    my %wanted = ( timeout => 30,
                   errMode => 'die',
                   errTries => 3,
                   debug    => undef,
                   debugExp => 0,
                   liveExp  => 1,
                   expRaw   => 1,
                   aggressive => 0,
                   sticky     => 0,
                   ignoreSecWarn => 0,
                 );
    my %rets = ();
    for (keys %wanted) { $rets{$_} = $object->{$_} };
    eq_or_diff(\%rets,\%wanted,"constructor - default values correct");
}

sub test_constructor_params {
    my %wanted = ( timeout => 300,
                   errMode => 'return',
                   errTries => 1,
                   debug    => 1,
                   debugExp => 1,
                   liveExp  => 0,
                   expRaw   => 0,
                   aggressive => 1,
                   sticky     => 1,
                   ignoreSecWarn => 1,
                 );
    my $object = $class->build(%wanted);
    my %rets = ();
    for (keys %wanted) { $rets{$_} = $object->{$_} };
    eq_or_diff(\%rets,\%wanted,"constructor - provided parameters override default");
    return 0;
}


sub test_log {
    # log is a file handle
    my $temp_fh   = File::Temp->new();
    my $file_name = $temp_fh->filename();
    my $object = $class->build(log => $temp_fh );
    my $log_message = "test the log target to a file handle\n";
    $object->_printlog("$log_message");
    close($temp_fh);
    open(my $fh, '<', $file_name ) or die "unable to open $file_name: $!";
    my $ret = join '', <$fh>;
    close( $fh );
    like($ret,qr/$log_message/,"constructor - log target is file handle");

    # log to a file 
    $temp_fh   = File::Temp->new();
    $file_name = $temp_fh->filename();
    close($temp_fh);
    $object = $class->build(log => $file_name);
    $log_message = "test the log target to a file\n";
    $object->_printlog("$log_message");
    undef $object;
    open($fh, '<', $file_name ) or die "unable to open $file_name: $!";
    $ret = join '', <$fh>;
    close( $fh );
    like($ret,qr/$log_message/,"constructor - log target is a file");

    # log to a Angelfile.log
    my $file = "./Angelfile.log";
    if ( -f $file ) {
        unlink $file or die "can not remove $file: $!\n";
    }
    $object = $class->build();
    $log_message = "test the log target to $file\n";
    $object->_printlog("$log_message");
    undef $object;
    open($fh, '<', $file) or die "unable to open $file: $!";
    $ret = join '', <$fh>;
    close( $fh );
    like($ret,qr/$log_message/,"constructor - log target is $file");

    return 0;
}

sub test_initial_state {
    my $object = $class->build( name => 'initial_state', descr => 'my first test state');
    my %wanted = ( name => 'initial_state', descr => 'my first test state', prompt => 'MATCHNOTHING' );
    my $ret = shift @{$object->{'state'}};
    eq_or_diff($ret,\%wanted,"constructor - initial state is set");
}


