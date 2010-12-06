use Test::Differences;    # qw(eq_or_diff);
use Test::Exception;      # qw(throws_ok)
use Test::More 'no_plan'; #tests => 2;
require( 'lib/Expect/Angel.pm' );
our $class = 'Expect::Angel';


# prepare
my $hostname = 'Router';
my $states = [(
               { prompt => "rommon> ?\$",       # state 1
                 name   => "rommon",
                 descr  => "rom monitor"
               },
               { prompt => "$hostname> ?\$",    # state 2
                 name   => "non_privilege",
                 descr  => "non_privilege mode"
               },
               { prompt => "$hostname# ?\$",    # state 3
                 name   => "enable",
                 descr  => "enable mode"
               },
               { prompt => "$hostname\\\(conf(ig)?.*\\\)# ?\$",   # state 4
                 name   => "config",
                 descr  => "configuration model"
               },
            )];
my $object = $class->build();
$object->addState(%$_) for (@$states);

test_cmdexe_simple();
test_cmdexe_complex();

sub test_cmdexe_simple {
    {
        no strict qw(refs);          ## no critic (ProhibitNoStrict)
        no warnings qw(redefine);    ## no critic (ProhibitNoWarnings)
        
        # move state
        my ($move_state_to); # the current state after execute this mothod
        my ($move_state_return);  # 0|1
        my ($move_state_times);  # number of called
        local *{'Expect::Angel::movState'} = sub {
             my ( $this, $state) = @_;
             $this->{'current'} = $move_state_to;
             $move_state_times++;
             return $move_state_return;
        };  
        local *{'Expect::Angel::_movState'} = *{'Expect::Angel::movState'};

        # can always be back to initial state
        my ($state0_times);
        local *{'Expect::Angel::state0'} = sub {
             my ($this) = @_;
             $self->{current} = 0;
             $state0_times++;
        };

        my (%cmd_sent);  # catch the cmd that got executed
        my $cmd_sent_success = 1; 
        local *{'Expect::Angel::sendCmd'} = sub {
             my ($this,$cmd) = @_;
             if (exists $cmd_sent{"$cmd"}) {
                 $cmd_sent{"$cmd"}++;
             } else {
                 $cmd_sent{"$cmd"} = 1;
             }
             return $cmd_sent_success;
        };

        # $msg, and $result are required by this method, so that the returned 
        # code can be eval, and the values of $msg $result tells the result.
        # $result = 1, good, see prompt of one of stable state
        #         = 2, timeout when executing expect body
        #         = 3, eof when reading socket.
        my ($expect_return,$result);
        my ($msg);     # the required initial var by this method, should be set to "" before call
                       # the output of the DUT after the call
        my ($wanted_output);  # set this as the expected output by DUT 
        local *{'Expect::Angel::_buildCmdExpBody'} = sub {
             my ($this,$expect_body) = @_;
             return "\$result = $expect_return;\$msg = \"$wanted_output\";";
        };

        # command
        #   - single command
        #   - list of command
        # command executes statue
        #   - success 
        #     - at right state
        #     - at another state
        #     - at another state, but need to move because of sticky is set
        #   - fail 

        my ($dut_output,$cmd,%wanted_executed_cmd); 
        my $target_state = 2;

        # single command, success, same state after execution
        $cmd = "single command";
        $object->{'current'} = 2;
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1;
        $expect_return = 1; # success
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd);
        ok("$dut_output" eq "$wanted_output", "cmdexe - $wanted_output");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got executed");

        # single command, failed, tried errTries time, move state success
        $object->{'errMode'} = 'return'; # so that we can compare
        $object->{'current'} = $target_state;
        $move_state_to = $target_state; # the current state after execute this mothod
        $move_state_return = 1;  # 0|1
        $expect_return = 2; # failed to execute the command
        $wanted_output = "";  # set to any value
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_state0_times = $object->{'errTries'} - 1;
        $state0_times = 0; #reset
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = $object->{'errTries'};
        $dut_output = $object->cmdexe($cmd);
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got tried correct number of times");
        ok($state0_times == $wanted_state0_times, "cmdexe - $cmd failed, back to state0 cycle right");
        ok(! defined $object->cmdexe($cmd), "cmdexe - $cmd failed, return undef if errMode defines return");

        # single command, failed, errMode is die, should die
        $object->{'errMode'} = 'die'; # so that we can compare
        throws_ok { $object->cmdexe($cmd) } qr/Failed to execute $cmd/,
                "single command, failed, errMode is die, should die";
       
        # single command, failed, errMode is code, should execute the code
        my ($errhandle_code);
        $object->{'errMode'} = sub { my $error = shift; $errhandle_code = $error; };
        my $wanted = "Failed to execute $cmd";
        ok(! defined $object->cmdexe($cmd), "cmdexe - $cmd failed, return undef if errMode defines code");
        ok($errhandle_code eq $wanted, "cmdexe - $cmd failed, code is executed if errMode defines code");

        # single command, failed, move state failed too
        $object->{'errMode'} = 'return'; # so that we can compare
        $object->{'current'} = $target_state;
        $move_state_to = $target_state - 1; # the current state after execute movState, moveState error
        $move_state_return = 0;  # 0|1
        $expect_return = 2; # failed to execute the command
        $wanted_output = "";  # set to any value
        $msg = "";  # required var by _buildCmdExpBody
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1; # just send once by sendCmd, the rest is for movState. $object->{'errTries'};
        $dut_output = $object->cmdexe($cmd);
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got tried correct number of times, including movState");
        ok(! defined $object->cmdexe($cmd), "cmdexe - $cmd failed, return undef if errMode defines return");

        # single command, success, but one another state,  move state back failed
        local *{'Expect::Angel::_buildCmdExpBody'} = sub {
             my ($this,$expect_body) = @_;
             $this->{'current'} = $target_state + 1;  # another state
             return "\$result = $expect_return;\$msg = \"$wanted_output\";";
        };
        $object->{'errMode'} = 'return'; # so that we can compare
        $object->{'current'} = $target_state;
        $object->{'sticky'} = 1;
        $move_state_to = $target_state - 1; # the current state after execute movState, moveState fail
        $move_state_return = 0;  # 0|1
        $expect_return = 1; # execute the command success
        $wanted_output = "";  # set to any value
        $msg = "";  # required var by _buildCmdExpBody
        %cmd_sent = ();  # catch the cmd that got executed
        $cmd = "single command";
        $wanted_executed_cmd{$cmd} = 1; # just send once by sendCmd, the rest is for movState. $object->{'errTries'};
        $move_state_times = 0;
        $dut_output = $object->cmdexe($cmd);
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd success, sticky is set, executed once ");
        ok(! defined $dut_output, "cmdexe - $cmd success, return undef due to failed to move state back");
        ok($move_state_times == $object->{errTries}, "cmdexe - $cmd success, sticky is set, tried to move back times");

        # single command, success, but one another state,  move state back success
        local *{'Expect::Angel::_buildCmdExpBody'} = sub {
             my ($this,$expect_body) = @_;
             $this->{'current'} = $target_state + 1;  # another state
             return "\$result = $expect_return;\$msg = \"$wanted_output\";";
        };
        $object->{'errMode'} = 'return'; # so that we can compare
        $object->{'current'} = $target_state;
        $object->{'sticky'} = 1;
        $move_state_to = $target_state; # the current state after execute movState, moveState success
        $move_state_return = 1;  # 0|1
        $expect_return = 1; # execute the command success
        $wanted_output = "";  # set to any value
        $msg = "";  # required var by _buildCmdExpBody
        %cmd_sent = ();  # catch the cmd that got executed
        $cmd = "single command";
        $wanted_executed_cmd{$cmd} = 1; # just send once by sendCmd, the rest is for movState. $object->{'errTries'};
        $move_state_times = 0;
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd);
        print "$move_state_times\n";
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd success, sticky is set, executed once ");
        ok($move_state_times == 1, "cmdexe - $cmd success, sticky is set, move back success");
        ok("$dut_output" eq "$wanted_output", "cmdexe - $cmd success with sticky set, can move back, output correct");

    };  
 
    return 0;
}


sub test_cmdexe_complex {
    {
        no strict qw(refs);          ## no critic (ProhibitNoStrict)
        no warnings qw(redefine);    ## no critic (ProhibitNoWarnings)
        
        # move state
        my ($move_state_to); # the current state after execute this mothod
        my ($move_state_return);  # 0|1
        my ($move_state_times);  # number of called
        local *{'Expect::Angel::movState'} = sub {
             my ( $this, $state) = @_;
             $this->{'current'} = $move_state_to;
             $move_state_times++;
             return $move_state_return;
        };  
        local *{'Expect::Angel::_movState'} = *{'Expect::Angel::movState'};

        # can always be back to initial state
        my ($state0_times);
        local *{'Expect::Angel::state0'} = sub {
             my ($this) = @_;
             $self->{current} = 0;
             $state0_times++;
        };

        my (%cmd_sent);  # catch the cmd that got executed
        my $cmd_sent_success = 1; 
        local *{'Expect::Angel::sendCmd'} = sub {
             my ($this,$cmd) = @_;
             if (exists $cmd_sent{"$cmd"}) {
                 $cmd_sent{"$cmd"}++;
             } else {
                 $cmd_sent{"$cmd"} = 1;
             }
             return $cmd_sent_success;
        };

        # $msg, and $result are required by this method, so that the returned 
        # code can be eval, and the values of $msg $result tells the result.
        # $result = 1, good, see prompt of one of stable state
        #         = 2, timeout when executing expect body
        #         = 3, eof when reading socket.
        my ($expect_return,$result);
        my ($msg);     # the required initial var by this method, should be set to "" before call
                       # the output of the DUT after the call
        my ($wanted_output);  # set this as the expected output by DUT 
        local *{'Expect::Angel::_buildCmdExpBody'} = sub {
             my ($this,$expect_body) = @_;
             return "\$result = $expect_return;\$msg = \"$wanted_output\";";
        };

        my ($dut_output,$cmd,%wanted_executed_cmd); 
        my $target_state = 2;

        # with same state, single command success
        $cmd = "single command";
        $object->{'current'} = $target_state;
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1;
        $expect_return = 1; # success
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd,$target_state);
        ok("$dut_output" eq "$wanted_output", "cmdexe - $cmd success, with same state provided");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got executed once");

        # with different state, move state failed
        $cmd = "single command";
        $object->{'current'} = $target_state - 1;
        $move_state_to = $target_state + 1; # can not move to specified state
        $move_state_return = 1;  # 0|1, doesn't matter
        %cmd_sent = ();  # catch the cmd that got executed
        %wanted_executed_cmd = ();
        $move_state_times = 0;
        $dut_output = $object->cmdexe($cmd,$target_state);
        ok(! defined $dut_output, "cmdexe - $cmd not executed, with different state provided, failed to transit state");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd not executed, move state failed ");
        ok($move_state_times == 1, "cmdexe - $cmd not executed, tried to move state");

        # with different state, move state success
        $cmd = "single command";
        $object->{'current'} = $target_state - 1;
        $move_state_to = $target_state; # can move to specified state
        $move_state_return = 1;  # 0|1
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1;
        $expect_return = 1; # success
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd,$target_state);
        ok("$dut_output" eq "$wanted_output", "cmdexe - $cmd success, with different state provided");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got executed once");

        # only expect, there should not be transit state
        my $expect_body_got;
        local *{'Expect::Angel::_buildCmdExpBody'} = sub {
             my ($this,$expect_body) = @_;
             $expect_body_got = $expect_body;
             return "\$result = $expect_return;\$msg = \"$wanted_output\";";
        };
        $cmd = "single command";
        my $expect_body_set = [{
                    'Target IP address or host   : ' => "1.1.1.1",
                    'Repeat Count \[5\]    : ?'     => '',
                    'Datagram size \[100\] : ?'     => '',
                    'Timeout in secs \[2\] : ?'     => '',
                    'Extended commands \[n\] : ?'   => '',
                    'Sweep range of sizes \[n\]: ?' => '',
                  }];
        $object->{'current'} = $target_state;
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1;
        $expect_return = 1; # success
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd,$expect_body_set);
        ok("$dut_output" eq "$wanted_output", "cmdexe - $cmd, with expect provided");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd got executed once");
        eq_or_diff($expect_body_got,$expect_body_set,"cmdexe - $cmd, expect body correctly built");

        # both expect and state
        $object->{'current'} = $target_state - 1;
        $move_state_to = $target_state; # can move to specified state
        $move_state_return = 1;  # 0|1
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$cmd} = 1;
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "$cmd success";  # set to any value
        $dut_output = $object->cmdexe($cmd,$expect_body_set,$target_state);
        ok("$dut_output" eq "$wanted_output", "cmdexe - $cmd, with expect and state provided, output correct");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - $cmd, with expect and state provided, got executed once");
        eq_or_diff($expect_body_got,$expect_body_set,"cmdexe - $cmd, with expect and state provided, expect body correctly built");

        # list of commands
        %wanted_executed_cmd = ();
        my @cmd = ("one command", "another command", "last command");
        $object->{'current'} = $target_state;
        %cmd_sent = ();  # catch the cmd that got executed
        $wanted_executed_cmd{$_} = 1 for (@cmd);
        $expect_return = 1; # success
        $result = 0;
        $msg = "";  # required var by _buildCmdExpBody
        $wanted_output = "last commmand success";  # set to any value
        $dut_output = $object->cmdexe(\@cmd);
        ok("$dut_output" eq "$wanted_output", "cmdexe - list commands success, output check");
        eq_or_diff(\%cmd_sent,\%wanted_executed_cmd,"cmdexe - list commands success, all executed");

    };  
 
    return 0;
}




