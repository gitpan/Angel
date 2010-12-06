use Test::Differences;    # qw(eq_or_diff);
use Test::Exception;      # qw(throws_ok)
use Test::More 'no_plan'; #tests => 2;
use File::Temp ();
require( 'lib/Expect/Angel.pm' );
#BEGIN { use_ok('Expect::Angel') };
our $class = 'Expect::Angel';

test_addState();
test_transitState();
test_movState();

sub test_addState {
    my $object = $class->build();

    # customerized state
    my %state1 = ( name => 'state_one', descr => 'my first test state', prompt => 'CustomPrompt1\s.*');
    my %wanted = %state1;
    $object->addState(%state1);
    my $ret = $object->{'state'}[-1];  # last newly-added state data struct
    eq_or_diff($ret,\%wanted,"addState - customerized state");
  
    # by means of default
    %state1 = ( prompt => 'CustomPrompt2\s.*');
    my $added_state = $object->addState(%state1);
    %wanted = ( name => "state$added_state", descr => "state$added_state", prompt => 'CustomPrompt2\s.*');
    $ret = $object->{'state'}[-1];  # last newly-added state data struct
    eq_or_diff($ret,\%wanted,"addState - customerized state");
}


sub test_transitState {
    my ($trans,%ret,%wanted,$from,$to,$ret);
    # add a few states
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
    my @ret_states = @{$object->{'state'}};  # all states
    shift @ret_states;  # get rid of the initial one
    eq_or_diff(\@ret_states,$states,"addState - add a few states");

    # add transition by state number
    $from = int rand (1 + @$states);  # from 0 to 4 
    while ( ($to = int rand (1 + @$states)) == $from) {};  # different from $from
    $trans = {nexthop => 2};
    $object->transitState($from,$to,$trans);
    %wanted = %$trans;
    $ret = $object->{'state'}[$from]{'trans'}{$to}; 
    eq_or_diff($ret,\%wanted,"transitState - by state number");

    # add transition by state name
    $from = 1 + int rand @$states;  # from 1 to 4 
    while ( ($to = int rand (1 + @$states)) == $from) {};  # different from $from
    my $from_name = $states->[$from - 1]{'name'};
    my $to_name = ($to == 0) ? 'state0' : $states->[$to - 1]{'name'};
    $object->transitState($from_name,$to_name,$trans);
    $ret = $object->{'state'}[$from]{'trans'}{$to}; 
    eq_or_diff($ret,\%wanted,"transitState - by state name");

    # add transition by state number, and Expect body
    $from = int rand (1 + @$states);  # from 0 to 4 
    while ( ($to = int rand (1 + @$states)) == $from) {};  # different from $from
    $trans = { command => 'my command',
                expect => [{ 'Username: \r?$' => 'user',
                                'login: \r?$' => 'user\r',
                             'password: \r?$' => "passwd"},
                           { 'telnet> \r?$' => 'quit\n' },
                           {'.+' => '\x1d' }
                          ]
             };
    $object->transitState($from,$to,$trans);
    my $wanted = { command => 'my command',
                expect => [{ 'Username: \r?$' => 'user\r',   # should be added by method
                                'login: \r?$' => 'user\r',   # already exists
                             'password: \r?$' => 'passwd\r'  # should be added by method
                           }, 
                           { 'telnet> \r?$' => 'quit\n' },   # should not change
                           {'.+' => '\x1d' }                 # should not change
                          ],
             };
    $ret = $object->{'state'}[$from]{'trans'}{$to}; 
    eq_or_diff($ret,$wanted,"transitState - trailing dash_r in Expect body");

    return 0;
}

sub test_movState {
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

    {
        no strict qw(refs);          ## no critic (ProhibitNoStrict)
        no warnings qw(redefine);    ## no critic (ProhibitNoWarnings)
        
        # return true if move success
        local *{'Expect::Angel::_movState'} = sub {
             my ( $this, $state) = @_;
             $this->{'current'} = $state;
             return 1;
        };  
        my $target_state = 2;
        ok($object->movState($target_state), "moveState - return true when move success");
        ok($object->{'current'} == $target_state, "moveState - current state correct when move success");

        # try errTries times when fail, and return undef
        $target_state = 3;
        local *{'Expect::Angel::_movState'} = sub {
             my ( $this, $target_state) = @_;
             return undef;
        };  
        my $state0_times = 0;
        local *{'Expect::Angel::state0'} = sub {
             my ($this) = @_;
             $self->{current} = 0;
             $state0_times++;
        };
        ok(!defined($object->movState($target_state)), "moveState - return undef when move failed");
        ok($state0_times == $object->{'errTries'} - 1, "moveState - tried specified times when failed");

    };  
 
    return 0;
}


