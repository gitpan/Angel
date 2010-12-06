package Expect::Angel;
use strict;
use warnings;
use Term::ReadKey;
our $VERSION = '1.01';
use Expect;
my ($debug);

=head1 NAME

Expect::Angel - Build up a robust connection class to your DUT (Router/Switch/Host)

=head1 SYNOPSIS

  use Expect::Angel;
  @ISA = ("Expect::Angel");
  sub new {
     my $type = shift;
     my $para = {@_};
     my $conn = $type->build(%$para);
     ... ...
     return $conn;
  }

  # move to config mode of the device
  sub configMode {
     my ($conn) = shift;
     $conn->movState("config") or return undef;
  }

  # at your derived module, you can easily do the following jobs.
  # capture output of a command execution
  my @ints = $conn->cmdexe("show int brief");

  # executes a list of commands at "config" mode of Cisco device
  my @cmd = ("interface e0/0",
             "ip address 10.1.1.10 255.2555.255.0",
             "no shut",
             "exit",  
             "interface e0/1",
             "ip address 10.1.2.100 255.2555.255.0",
             "no shut"
            );
  $conn->cmdexe(\@cmd, "config");

  # always stay at config mode for each command execution, although
  # existing some command that may change mode inadvertently.
  $conn->sticky(1);
  my @cmd = ("interface e0/0",
             "ip address 10.1.1.10 255.2555.255.0",
             "end",  # NOTE, this cause the transition to "enable" mode
             "interface e0/1",
             "ip address 10.1.2.100 255.2555.255.0",
             "no shut"
            );
  $conn->cmdexe(\@cmd, "config");
  

=head1 DESCRIPTION

If you are looking for a module that can help you to quickly build up a robust connection to your DUT (Device under Test), here is the right place!

Angel is just like a messenger between your testing machine, where everyting is perfect like heaven, and DUT, where exists right and wrong like earth. The messenger must tolerate the errors and disasters occuring on DUT and faithful deliver information to and from the DUT.

Angel is built on Expect.pm module, but hides the complexity of it. With Angel.pm You can easily build an object-oriented module that meets your specific need with the most useful methods inherited from Angel.

Let's take CISCO router as the first example.

 CISCIO Router

 Modes:  Non-privilege  --- (enable) ---> Enable Mode -- (config t) --> Config Mode

                        <-- (exit) ------             <-- (exit) -----

Here the router has 3 modes, Non-privilege, Enable, and Config. When executing enable command at 1st mode, it transits to Enable mode, and so on as shown.


General speaking, DUT is a network appliance that provides CLI (command line interface) for user to configure and manupulate. It's very often that a DUT presents multiple states, each grants a level of privileges.

  DUT:    state0  ---->  state1  ----->  state2 ... ... -----> stateN   
                  <----          <-----                 <-----

Each state is a stable mode of the DUT, at which the DUT may accept an input and execute it as a command.
Each state has its own prompt and a set of commands appropriate to this state. The commands under a state can be put into categories.

  1. After execution the state keeps the same. 

  2. After execution the state transits to another one. 

  3. The execution will show more prompt asking for more input, and eventually back to the some state.

The state transition may happen between two adjacent states, or skip some states.

Your task is to tell Angel the following information for a specific DUT. 

  1. describes the states and their prompts

  2. describes the state transition

Angel provides you: 

 1. Maintain the connection to DUT.

 2. Send command to DUT at each state and retrieve response of the command.

 3. Error handling.

 4. Log the messages exchanged.



=head2 constructor
 - build({ key1 => val1, ... , keyN => valN})

  Function: create the DUT object.

  - build({ timeout => $in_seconds,     # default is 30 seconds
            errMode => 'die|return|$handler ' # default is die, you can provide your own handler
            errTries => $number,        # default is 3
            log => $file,               # default is ./Angelfile.log, you can put filename|filehandle
            debug => 1,                 # default is 0, Angel debug info
            debugExp => 1,              # default is 0, Expect debug info
            liveExp => 1,               # default is 1, Expect's log_user
            expRaw  => 1,               # default is 1, Raw mode of terminal driver.
            user    => user_name        # used to connect to DUT. If none provided,
                                          will be asked in from keyboard 
            passwd   => password        # used to connect to DUT. If none provided, 
                                          will be asked in from keyboard
            aggressive => 0|1           # default is 0, see explanation below.
            others => values            # see below
          })

 Function: create the DUT object 

   Some parameters are self explained.

   timeout - after a command is sent to DUT, the response is expected to return without it.
   Longer than timeout is regarded as a failure and counted in errTries.

   log - indicates the target of log created by this module and Expect. The log may contain 
   all commands and intermediate prompts between Angel and DUT as well as Expect debug 
   information that are controlled by "debug" and "debugExp". The log message will be 
   written to the file specified by file_name, or File_handle if you have your own log 
   framework. If none is seen, Angelfile.log at current directory is used.

   aggressive - controls the state transition behavior. There are two ways in transition.
      - aggressive
       If transition is defined from a state to another, it will try to move directly.
       otherwise, try one hop backward of the target.
           for example, current state = 1, target state = 4
           if defined transition to state 4, then go directly;
           otherwise, check if transition to state 3 is defined; if not, then try state 2, and so on.

      - non_aggressive (default)
       similiar to aggressive, but it tries one hop forward from the source
       i.e. if 1 to 4 fails, it tries to go to 2 first, then 2 to 4.

      This may affect you state transition design. The design should meet that there is a path
      from any source state to any target state.

   liveExp - controls live output from spawned process such as telnet or ssh. it's Expect's log_user().
   With this set to 1, you can see all the information exchanged by Angel.

   debugExp - controls expect debug message. If you turn it on, there will be huge Expect debug 
              messages printed out on screen

   others:
   sticky - controls state transition behavior after a command execution, see cmdexe() for detail.
   you can change it any time.

   ignoreSecWarn - If you run with debug enabled, the password is printed to log target,
   This may be a security exposure. So the default behavior is that Angel will print a 
   warning and wait for your confirmation on keyboard to continue. If you don't want this
   stop, you can set ignoreSecWarn => 1.

   defPattern - This is the default Expect pattern and action pairs.
   You can define the most common patterns here, which is added to the Expect body of
   all state transition and command execution, so that you don't need to include them in
   each state transition description or command. If you do define the patern at each individule
   one, it takes precedence over the default pattern. 
   One example is like this
     defPattern = [ { '[-]+\s*(More|more)\s*[-]+' => ' ',
                       '^.* memory\? *\[confirm\] *$' => '\r'},

                     { '^.*Are you sure\?.*\[confirm\] *$' => '\r',
                       '^.*Are you sure\?.*$'              => 'yes\r',
                       '^.*Are you sure you want to continue connecting\?.*$' => 'yes\r',
                     }
                   ]
   Its data structure is list of hash like this: [ {}, ... {} ]
   The list keeps the sequence in the pattern match, while the order does not matter in a hash.
   In another word, if the pattern match order does matter, you put them in different hash
   in preferred order, otherwise you can put them in the same hash.
   
   noechoback - controls if a command is expected to be echoed back. By default it doesn't exist
   and the command sent to DUT is expected to be back. This is true for Cisco and Juniper devices.
   In case your situation doesn't have this behivior, you can set this attribute to any value. 
   see sendCmd() method for more infomation.

=cut

sub build {
   my $type = shift;
   my $self = { @_ };
   bless $self, $type;
   $debug = 0;
   $self->{current} = 0;    # state
   $self->{sticky} = 0 unless (exists $self->{sticky});    # command sticky to a state?
   $self->{liveExp} = 1 unless (exists $self->{liveExp});  # log_user (log_stdout) of Expect
   $self->{expRaw} = 1 unless (exists $self->{expRaw});    # raw mode is default.
   $self->{ignoreSecWarn} ||= 0;                           # ignore secret exposure warning
   #
   # error handling
   #
   $self->{errTries} ||= 3;
   $self->{errMode} ||= 'die';
   $self->{timeout} ||= 30;
   $debug = $self->{debug} if (exists $self->{debug});
   $self->{debugExp} = 0 unless(exists $self->{debugExp});   # expect debug
   if ($self->{debug} && ! $self->{ignoreSecWarn}) {
       $self->_prtSecWarn() or exit;
   }
   #delete $self->{aggressive} unless(exists $self->{aggressive} && ! $self->{aggressive});
   $self->{aggressive} ||= 0;

   #
   # log
   #
   if (exists $self->{log} && ref $self->{log}) {
       $self->{logF} = $self->{log};
       $self->_printlog("log use existing file handle\n") if ($debug);
   } else {
       my ($logfile);
       if (exists $self->{log}) {
           $logfile = $self->{log};
       }else{
          #$self->{logF} = \*STDOUT, #log to STDOUT make output mess
          $logfile = "./Angelfile.log";
       }
       my $fh = IO::File->new(">$logfile") or die "can not open $logfile\n";
       $self->{logF} = $fh;
       select( (select($fh), $| = 1)[0]);
   }
   if ($debug) {
       $self->_printlog("attributes of the object\n");
       for (qw(liveExp expRaw sticky debugExp ignoreSecWarn aggressive errTries errMode)) {
           $self->_printlog("$_ => $self->{$_}\n");
           $self->_printlog("debug => $debug\n");
       }
   }

   #
   # add init state and one if defined by caller class, 
   #
   my %init = map { $_ => $self->{$_} } grep { /^name|descr|prompt$/ } keys %$self;
   $self->addState(%init);
   return $self;
}

=head2 addState(name => state_name, descr => "blar blar", prompt => 'switch \r?$')

 Function: to add a state 
    If a value not defined, it will be stateN, where N is "state seqence number"
    The initial state, which is 0, will use descr => "initial state", prompt => 'MATCHNOTHING" by default.
 return state sequence number of this state

 descr: description of this state, used for human readable purpose only.
 name: name of the state, unique in all states, default states would be 0, 1, 2, etc. 
       State is identified by either the sequence number (0 is the initial state), or the name.
 prompt: prompt of this state, in perl regular expression

 After the call, a state data structure is appended to state list.
 state => [ # no.0 state 
            { name => "state_name",  # must have letter, state0 is the default
                                    # for 'initial state.
              descr => "Printable strings"  # purely for human readable
                                            # 'initial state' for 1st state by default
              prompt => reg(RE); # regular expression of the state
                                 # this is to match prompt of the socket
            },

            # more state
            { },
         ]

=cut

sub addState {
   my $self = shift;
   my $mode = {@_};
   $self->{state} = [] unless(exists $self->{state});
   my $no = @{$self->{state}};

   # initial state is 0
   if ($no == 0) {
      $mode->{descr} = (exists $mode->{descr}) ? "$mode->{descr}" : 'initial state'; 
      $mode->{prompt} = (exists $mode->{prompt}) ? "$mode->{prompt}" : 'MATCHNOTHING'; 
   }

   # if any key not specified, stateN is used.
   for (qw(name descr prompt)) {
      $mode->{$_} = "state".$no unless(exists $mode->{$_});
   }

   push @{$self->{state}}, $mode;
   return @{$self->{state}} - 1;
}

=head2 transitState($from,$to,$transDefinition)

   Add a transition definition from $from state to $to state.
   $from: source state name or number 
   $to:   destination state name or number
   $transDefinition: ref to hash body defining how to do the transition
   return: previous transition definition from $from to $to if defined, or undef

   $transDefinition is defined like this
     { command => "executable command at the state",
       expect => [ { hint/answer block }, ... {} ]
     }
     or
     { command => [("one command","another command", ... ,"last cmd")],
       expect => [ { hint/answer block }, ... , {} ]
     }

     hint/answer bloc
     could be none, {}, means no interactive action duration transition
     hint => reg(RE);  # regular expression for system response to go to that state
                       # password is one example
     answer => "answer to the hint in order to go that state", "\r" or "\n" is auto added

     or

     { nexthop => state_name or number }

     They are mutual exclusive. If both exists, nexthop will take precedence, i.e, try to
     go to the state first, then make follow whatever defined at that state.

   Note to $transDefinition -- This ref is directly assigned to the internal data structure
   without deep copy. It is caller's responsibility to assign a new memory location for each
   call as shown above.

=cut

sub transitState {
    my ($self,$from,$to,$trans) = @_;
    my $msg = "$from and/or $to not found";
    $from = $self->_getNofromName($from) unless ($from =~ /^\d+$/);
    $to = $self->_getNofromName($to) unless ($to =~ /^\d+$/);
    die "\n$msg\n" unless(defined $from and defined $to);
    # check if action ends with "\r", add it if not.
    $self->_addDashr($trans->{expect}) if (exists $trans->{expect});

    my $old = $self->{state}[$from]{trans}{$to} if (exists $self->{state}[$from]{trans}{$to});
    $self->{state}[$from]{trans}{$to} = $trans;
    (defined $old) ? $old : undef;
}

=head2 catState

    Print all the defined states for debug. 
    Note, the credential may be printed out by this

=cut

sub catState {
   my $self = shift;
   my ($current,$state) = ($self->{'current'},$self->{'state'});
   print "\n==================================\n";
   print "State Report: current state => $current\n";
   print "==================================\n";
   my $i = 0;
   for my $as (@$state) {
      print "\n(",$i++,")-->";
      for (qw(name descr prompt)) {
         print "$_: <$as->{$_}>\n";
      }
      for my $trans (sort keys %{$as->{trans}}) {
         print "to $trans -->\n";
         my $para = $as->{trans}{$trans};
         if (exists $para->{command}) {
            if (ref $para->{command}) {
                print "\tcommand => @{$para->{command}}\n";
            } else {
                print "\tcommand => $para->{command}\n";
            }
            for my $one (@{$para->{expect}}) { 
                for (keys %$one) { 
                    #_shield
                    print "\twhen see <$_> => send <$one->{$_}>\n"
                }
            }
         }else{
            for (keys %$para) { print "\t$_ => $para->{$_}\n" };
         }
      }
   }
   print "===== End of Report ====\n\n";
}

=head2  movState($state)

 Move to $state from whatever current state is. It will try its best anyway up to errTries times.
 After the first time fails, it moves state to initial state, then go to $state afterwards. 
 If errTries times has been tried and still failed, it keeps the best achieved state and return undef.
 return: true if successful, new current state = $state
         undef otherwise

=cut

sub movState {
   my ($self, $state) = @_;
   $state = $self->_getNofromName($state) unless ($state =~ /^\d+$/);
   my $try = $self->{errTries};
   while ($try-- > 0) {
      $self->state0 if ($try < $self->{errTries} - 1);
      $self->_movState($state);
      return 1 if ($self->{current} == $state);
   }
   return undef;
}

=head2  sticky()

   set or get sticky attribute of the object.
   sticky controls state transition behavior after a command execution, see cmdexe() for detail.
   input: optional, true|false, it's set if provided, otherwise it returns the current value.

=cut

sub sticky {
   my ($self, $set) = @_;
   if (defined $set) {
       $self->{sticky} = $set ? 1 : 0;
       $self->_printlog("sticky is set to <$self->{sticky}>\n") if ($debug);
   }else{
       return $self->{sticky};
   }
}

# move from current state to $to state, just try once
# may involve recursive transitions if no direct path from current to $to exists.
# return true : if succesfully move to the state, 
#        undef: otherwise
sub _movState {
   my ($self,$to) = @_;
   my $nexthop;
   my $errMsg = "can not find the name $to";
   $to = $self->_getNofromName($to) unless ($to =~ /^\d+$/);
   die "\n$errMsg\n" unless(defined $to);
   return 1 if ($self->{current} == $to);
   $self->_printlog("state transition $self->{current} -> $to\n") if ($debug);
   my $trans = $self->{state}[$self->{current}]{trans};
   if (defined $trans->{$to}) {
      if (exists $trans->{$to}{nexthop}) {
         $self->_printlog("\tnexthop specified, try $self->{current} -> $trans->{$to}{nexthop}\n") if ($debug);
         $self->_movState($trans->{$to}{nexthop}) or return undef;
      }else{
         return undef unless($self->_goState($to));
         # the current state is determined by auto detect
         # if it's not $to, the recursive transition continues.
         ###$self->{current} = $to; # not necessary
      }
   }elsif($to > $self->{current} + 1) {
      $nexthop = $self->{current} + 1;
      $nexthop = $to - 1 if ($self->{aggressive});
      $self->_printlog("\tdirect transition not defined, try $self->{current} -> $nexthop\n") if ($debug);
      $self->_movState($nexthop) or return undef;
   }elsif($to < $self->{current} - 1) {
      $nexthop = $self->{current} - 1;
      $nexthop = $to + 1 if ($self->{aggressive});
      $self->_printlog("\tdirect transition not defined, try $self->{current} -> $nexthop\n") if ($debug);
      $self->_movState($nexthop) or return undef;
   }else{
      # this is error in development stage, should bait out.
      die "\n$to has not defined at current state $self->{current}\n";
   }
   ##print "target: <$to>, current: <$self->{current}>\n"; ##
   $self->_movState($to) or return undef unless($self->{current} == $to);
}

=head2 state0

  Close the socket and set the object to initial state. It doesn't try to go over 
  the state transition from current to 0 like movState(0) does, instead, it directly 
  calls soft_close() of Expect to close the connection.
  But it keeps all the object properties and state transition date, so it helps to 
  re-transit to a state from initial in case it has experienced a problem in previous 
  attempt.   If a decent goodbye is required, movState(0) is the best solution.

=cut

sub state0 {
   my ($self) = @_;
   $self->{current} = 0;
   eval {$self->{host}->soft_close()};
   $self->_printlog("back to initial state 0\n") if ($debug);
   delete ($self->{host});
}

=head2 cmdexe(cmd,expect,state)

 Execute the command(s)
 cmd: scalar or list, means one command or a list of command to be executed
 expect: optional, ref to list of hash that describes the interactive expect body for this/these commands.
         [ { pattern1 => action1 }, ... {} ]
         If cmd is a list, then expect will be used in execution of all the commands in the list.
 state: optional, specifies the state at which the command(s) to be executed.
         Default is current state.
         If specified, cmdexe will go to the state and execute the command(s)
 return: the output of the last command execution. In list context it returns line by line,
         without \n, in scalar context, it returns the string of the output.
 Notes: The starting state is either specified by $state or current state. 
        The state may change during the cmd execution. If object's "sticky" is set, 
        it always tries to go back to starting state after each cmd execution. 
        Otherwise, it leaves whatever state it is cuased by the cmd execution. 
        So this attribute affects the rest of command(s).

 In case error happens when a command is executed, it will try errTries times (defualt is 3),
 each time it moves state back to 0, and goes to starting state, and executes the command again. 
 The state transition failure is counted in errTries. The errTries is reset for each command. 
 If errTries times  has been tried and still failed, it takes action defined by errMode, 
 i.e, die, return, or exectues a code, then return false condition.
       
=cut

sub cmdexe {
    my ($self, $cmd,$expect,$eState) = @_;
    my @cmds = ();

    # arguments tricks
    if (ref $cmd eq 'ARRAY') {
        @cmds = @$cmd;
    }else{
        push @cmds, $cmd;
    }
    if ($expect && ! ref $expect) {
        $eState = $expect;
        $expect = [];
    }
        
    my $currState = $self->{current};
    my $exeState = $eState || $self->{current};
    $exeState = $self->_getNofromName($exeState) unless ($exeState =~ /^\d+$/);
    $self->movState($exeState) if ($currState != $exeState);
    $self->_errDispatch("Failed to transit to $exeState"), return undef if ($self->{current} != $exeState);
    $currState = $self->{current};

    # execute the command(s)
    my $msg = "";
    for $cmd (@cmds) { 
        my $try = $self->{errTries};
        $self->_printlog("executing <$cmd>\n") if ($debug);
        while ($try-- > 0) {
            my $result;
            $msg = "";
    
            unless ($self->sendCmd($cmd)) {
                $self->_errDispatch("<$cmd> not echoed back in $self->{errTries} times");
                return undef;
            }

            my $code = $self->_buildCmdExpBody($expect);
            eval "$code";
            $self->_printlog("expect result: <$result>\n") if ($debug);
            if ($result == 1) {
                # good, DUT is at one of stable state
                if ($self->{current} != $currState && $self->{sticky}) {
                    $try-- while( $try >= 0 && ! $self->_movState($currState));
                }
                if ($try < 0) {
                    $self->_errDispatch("failed to stick to starting state");
                    return undef;
                }else{
                    last; # this $cmd success, jump out of while($try)
                }
            }else{
                # timeout or lost connection, the current execution failed.
                if ($try > 0) {
                    # still have errTries quota
                    # try like this: back to initial state, transits to starting state.
                    $self->_printlog("no matching state, try from new connection\n") if ($debug);
                    $self->state0();
                    $try-- while($try > 0 && ! $self->_movState($exeState));
                    if ($try <= 0) {
                        $self->_errDispatch("failed to transit to starting state");
                        return undef;
                    }
                }else{
                    $self->_printlog("no matching state, $self->{errTries} times done\n") if ($debug);
                    $self->_errDispatch("Failed to execute $cmd");
                    return undef;
                }
            }
            # end of this try cycle, back to next try
        }
        # end of this command cycle, back to next command
        $self->_printlog("return of <$cmd> = <$msg>\n") if ($debug);
    }
    # only last command's output is captured and returned.
    $self->_processMsg($msg);
}

=head2 cmdSendCheck($cmd,$errorPattern,$interactiveBody)

 send $cmd and check if the command is complained by device.

 Some device rejects a command and feeds back some error message. If you want to detect 
 this, you can monitor the error message pattern from the real device. For example, Cisco
 switch prints something like "% error_message". Then, you specifiy $errorPattern, which
 is a regular expression in this method call.

 This method will exectues $cmd at current state and detect if $errorPattern matches its 
 output in each execution. If it is, meaning the command is rejected, it will return 
 immediatedly with undef. Otherwise it continues and return the real output of the execution
 of the last command.

 $cmd: single or ref to a list of commands.
 $errorPattern: RE of error pattern, like '^%' in cisco switch.
 $interactiveBody: optional, same as $expect defined in cmdexe() method, please see cmdexe().
 return: undef when $errorPattern matches, otherwise output of the last command

=cut

sub cmdSendCheck {
    my ($self, $cmd,$errorPattern,$interactiveBody) = @_;
    my @cmds = ();
    my $output;

    if (ref $cmd eq 'ARRAY') {
        @cmds = @$cmd;
    }else{
        push @cmds, $cmd;
    }
    for $cmd (@cmds) { 
        $output = ($interactiveBody) ? $self->cmdexe($cmd,$interactiveBody) : $self->cmdexe($cmd);
        return undef if ($output =~ /$errorPattern/); 
    }
    $self->_processMsg($output);
}

=head2 echo($cmd)
       echo($cmd,$expect)

 This method is deprecated in this version. Use cmdexe() instead.

 It executes $cmd at current state, and return the response of DUT in either array, or ref of the array. 

 It always expects current state's prompt after executes $cmd. If a command may cause 
 state transition, it's safe to use cmdexe(), which will tolerate any state match.

 some $cmd need to interact with DUT in terms that DUT waits for some input after 
 accepting $cmd. Multiple prompt phrases and answers may be exchanged before the $cmd 
 is done and final prompt shows up.

 One example is like '--More--' is shown up during the output, and this case can be defined 
 in def_pattern, which will be taken care of in the interactive way during this process

 $expect defines these interactive exchanges specifically for this $cmd.
  {"prompt phrase1 => answer1", ... , "prompt phraseN => answerN"}
  where "prompt phraseN (N = 1 ... N)" can be expressed in Regular Expression

 In case error happens when $cmd is executed, it will try errTries times (defualt is 3), 
 each time it moves state back to 0, and goes to current state, and executes the $cmd again. 
 If errTries times  has been tried and still failed, it takes action defined by errMode, 
 i.e, die, return, or exectues a code, then return false condition.

 The response from the execution of the command $cmd is returned, each line is an element. 
 Depending on the context to assign, it either returns reference or the list itself.

 # this will return a list and assigned to @msg;
   @msg = $conn->echo("ls -l");

 # this will return ref to a list and assigned to $msg;
   $msg = $conn->echo("ls -l");
       
=cut

sub echo {
   my ($self, $cmd, $expect) = @_;
   my @feedback = ();
    $self->_expDebugKnob($self->{debugExp});
   my $msg = $self->_expectecho("$cmd",$expect);
   unless(defined $msg) {
      $self->_errDispatch("Lost connection: $@");
   }else{
      if ($msg =~ /\n/) {
         @feedback = map { $_ ."\n" } split /\n/, $msg;
         unless(@feedback) {
            for ($msg =~ /\n/g) {push @feedback, "\n"}
         }
      }else{
         push @feedback, $msg;
      }
   }
   if (@feedback) {
      return wantarray ? @feedback: \@feedback;
   }else{
      return wantarray ? @feedback: undef;
   }
}

sub _processMsg {
    my ($self,$msg) = @_;
    $self->_printlog("response from command\n<$msg>\n") if ($debug);
    return $msg unless(wantarray); 
    split /[\r\n]+/, $msg;
}


=head2 robustecho($cmd,$retMsgPt,$rejectPattern)

 This method is deprecated in this version. Use cmdSendCheck() instead.

    Send an command to DUT may encounter 3 situations
    1. the command is slurped by DUT without rejection, the action success.
    2. the command is rejected by DUT with error message, the action is failed
    3. DUT is crashed by the command, the action cause catastrophe

    This method detects the situation and return true on No.1, false on No.2, and undef on No.3
    $retMsgPt is a ref to list, the response of DUT to $cmd is assiged to it.
    $rejectPattern is RE that tells the matched response is regarded as rejection message from DUT.
    If the No.3 happens, $retMsgPt will hold the error message.

=cut

sub robustecho {
    my ($self,$cmd,$retMsgPt,$rejectPattern) = @_;
    my ($msg,@msg);
    eval {
       if (ref($cmd) eq 'HASH') {
          my $command = $cmd->{cmd};
          my $expect = $cmd->{expect};
          @msg = $self->echo($command, $expect);
       }else{
          @msg = $self->echo("$cmd");
       }
    };
    if ($@) {
       @$retMsgPt = split /\n+/, $@;
       return undef;
    }else{
       @$retMsgPt = @msg;
       $msg = join "", @msg;
       if ($msg =~ /$rejectPattern/si) {
          return 0;
       }else{
          return 1;
       }
    }
}


sub getUsername {
    my ($self,$what) = @_;
    $what ||= '';
    print STDERR "$what username: ";
    chomp (my $name = <STDIN>);
    return $name;
}

#sub getPasswd {
#    my ($self,$what) = @_;
#    $what ||= '';
#    print STDERR "$what password: ";
#    my $tty = _setEcho('off');
#    chomp (my $passwd = <STDIN>);
#    _setEcho($tty);
#    print STDERR "\n";
#    return $passwd;
#}

sub getPasswd {
    my ($self,$what) = @_;
    $what ||= '';
    print STDERR "$what ";
    ReadMode 4;
    my $passwd = "";
    my $key;
    while (1) {
        while (not defined ($key = ReadKey(-1))) { } #waiting for key, this is non-block read 
        if ($key eq "\177") {
            print STDERR "\010 \010" if (length $passwd);
            chop $passwd;
        }elsif ($key =~ /\n/) {
            print "$key";
            last;
        }else{
            $passwd .= "$key";
            print STDERR "*";
        }
    }
    ReadMode 0; # Reset tty mode before exiting
    return $passwd;
}

sub _setEcho {
   my ($mode) = @_;
   chomp (my $tty = `stty -g`);
   if ($mode eq 'off') {
      system "stty -echo </dev/tty";
   }elsif ($mode eq 'on') {
      system "stty echo </dev/tty";
   }else{
      $mode =~ /^([:\da-fA-F]+)$/;
      system "stty $1 </dev/tty";
   }
   return $tty;
}

# build the expect body from input "$patList" and "$prompt" that are kept intact here.
# $patList: [{},...{}], where {} is patterns and actions, which requires "\r" ending
#        The expect body is built in the sequence of the list, but no order within each {}.
#        Upon pattern match, exp_continue is applied. So if you need order in patter match,
#        organizes patList well before call this sub. Group your pattern matches in the 
#        way that order among groups, no order in group, and put them in $patList.
# $prompts: [], once match, it stop and return success.
# return the expect body code, which can be "eval" directly,
# Note: it requires you define $result and $msg before you "eval" this returned code.
#       my ($msg,$result) = ("",0);
#       $msg is the output from DUT
#       $result = 1, good, see prompt of one of stable state
#               = 2, timeout when executing expect body
#               = 3, eof when reading socket.
sub _buildExpBody {
    my ($self,$patList,$prompts) = @_;
    my $code = '';

    # answerback in login
    #$code = '$self->{host}->slave->stty(qw(raw -echo));'."\n" if ($self->{current} == 0);
    $code .= '$self->{host}->expect($self->{timeout},'."\n";

    # Adding patterns
    for my $pats (@$patList) {
        # _shield
        $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$msg .= \$fh->before().\$fh->match(); \$fh->send(\"$pats->{$_}\"); \$self->_printlog('see <$_> input <$pats->{$_}>'\.\"\\n\") if (\$debug); exp_continue; } ],\n" for (keys %$pats);
    }   

    # Adding states prompt
    for my $prompt (@$prompts) {
        my $promptEsc = _escape($prompt);
        my $state = $self->_prompt2num($prompt);
        $code .= "\t[ '-re', \'$prompt\', sub { my \$fh = shift; \$msg .= \$fh->before(); \$result = 1; \$self->{current} = $state; \$self->_printlog(\"see prompt <$promptEsc> of state $state\"\.\"\\n\") if (\$debug); } ],\n";
    }
 
    # answerback in login
    if ($self->{current} == 0) {
        #$code .= "\t '-i', [\$user_spawn_id], [ '-re', \'.+\', sub { my \$fh = shift; my \$catch = \$fh->match(); \$fh->send(\"\$catch\"); \$self->_printlog(\"see and send answerback <\$catch>\"\.\"\\n\") if (\$debug); exp_continue; } ],\n";

    }

    # Adding others
    $code .= "\t[ eof => sub { \$result = 3; \$self->_printlog(\"end-of-file\\n\") if (\$debug);} ],\n";
    $code .= "\t[ timeout => sub { \$result = 2;  \$self->_printlog(\"timeout\\n\") if (\$debug); } ],\n";
    $code .= ");\n\n";

    # answerback in login
    if ($self->{current} == 0) {
    #    my $mode = $self->{expRaw};
    #    my $echo = $mode;
    #    $mode = $mode ? 'raw' : '-raw';
    #    $echo = $echo ? '-echo' : 'echo';
    #    $code .= "\$self->{host}->slave->stty(\"$mode\", \"$echo\");"."\n";
    }

    # debug info
    if ($debug) {
        for my $pats (@$patList) {
            # _shield
            $self->_printlog("\texpecting <$_> => <$pats->{$_}>\n") for (keys %$pats);
        }
        for my $prompt (@$prompts) {
            $self->_printlog("\tuntil prompt => <$prompt>\n");
        }
        $self->_printlog("\tby executing ...\n\n");
        $self->_printlog("$code\n");
    }
    return $code;
}


# build the expect body from default patterns and input "$expect", and state prompts
# "$expect" takes precedence over default patterns.
# return the expect body code, which can be "eval" directly,
# see _buildExpBody for some notes about how to call
sub _buildCmdExpBody {
    my ($self,$expect) = @_;
    my $prompt = [];
    my $patsList = [];

    # A command-specific pattern takes precedence over defPattern one
    if ($expect && @$expect) {
        $self->_addDashr($expect);
        push @$patsList, @$expect;
    }

    # defPattern is added, which is defined by caller for a specific class
    push @$patsList, @{$self->{defPattern}};

    # Adding states prompt
    push @$prompt, $self->{state}[$self->{current}]{prompt}; # always put current first.
    for my $state ( 0 ... scalar @{$self->{state}} - 1) {
        push @$prompt, $self->{state}[$state]{prompt};
    }

    return $self->_buildExpBody($patsList,$prompt);
}

sub  _escape {
    my ($prompt) = @_;
    $prompt =~ s|([\$\@\%])|\\$1|g;
    return $prompt;
}

sub _prompt2num {
    my ($self,$prompt) = @_;
    for my $state ( 0 ... scalar @{$self->{state}} - 1) {
        return $state if ("$prompt" eq "$self->{state}[$state]{prompt}");
    }
    return undef;
}

sub _expectecho {
   my ($self, $cmd, $expect) = @_;
   $self->{host}->clear_accum();
   my $try = $self->{errTries};
   while ($try-- > 0) {
      my $err = 0;
      my $msg = "";
      unless(defined $self->_expectprint("$cmd")) {
         $@ = "print to a dead IO";
         $self->_printlog("print to a dead IO") if ($debug);
         $err = 1;
      }elsif($expect) {
         my $status = 0;
         my $prompt = $self->{state}[$self->{current}]{prompt};
         if ($debug) {
            $self->_printlog("going to send command => <$cmd>\n");
            $self->_printlog("\texpecting $_ => $expect->{$_}\n") for (keys %$expect);
            $self->_printlog("\tuntil prompt => <$prompt>\n");
         }
         my $result;
         my $code = '$self->{host}->expect($self->{timeout},'."\n";
         for (keys %$expect) {
            if ($debug) {
               $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$msg .= \$fh->before().\$fh->match(); \$fh->send(\"$expect->{$_}\\n\"); \$self->_printlog('see <$_> input <$expect->{$_}>'\.\"\\n\"); \$self->_printlog('see <$_> input <$expect->{$_}>'\.\"\\n\"); exp_continue; } ],\n";
            }else{
               $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$msg .= \$fh->before().\$fh->match(); \$fh->send(\"$expect->{$_}\\n\"); \$self->_printlog('see <$_> input <$expect->{$_}>'\.\"\\n\"); exp_continue; } ],\n";
            }   
         }   
         $code .= "\t[ '-re', \'$prompt\', sub { my \$fh = shift; \$msg .= \$fh->before(); \$result = 1; \$self->_printlog(\"see current prompt <\$prompt>\"\.\"\\n\"); } ],\n";
         $code .= "\t[ eof => sub { \$result = 3; \$self->_printlog(\"end-of-file\\n\");} ],\n";
         $code .= "\t[ timeout => sub { \$result = 2;  \$self->_printlog(\"timeout\\n\"); } ],\n";
         $code .= ");\n\n";
         $self->_printlog("\tby executing ...\n\n$code\n") if ($debug);
         eval "$code";
         $self->_printlog("expect result: <$result>\n") if ($debug);
         $err = ($result == 1) ? 0 : 1;
      }else{
         my $result;
         $self->{host}->expect($self->{timeout},
                              [ '-re', '[-]+\s*(More|more)\s*[-]+', sub { $msg .= $self->{host}->before(); my $fh = shift; $fh->send(" "); exp_continue;}],
                              [ '-re',"$self->{state}[$self->{current}]{prompt}",sub { $msg .= $self->{host}->before(); $self->_printlog("see current prompt <$self->{state}[$self->{current}]{prompt}>\n"); $result = 1; } ],
                              [ eof => sub { $self->_printlog("end-of-file\n"); $result = 3; } ],
                              [ timeout => sub { $self->_printlog("timeout\n"); $result = 2; } ]);
         if ($result != 1) {
            $@ = "Never got response of \"$cmd\"";
            $err = 1;
         }
      }
      if ($err) {
         $self->_printlog("$@, reconnect again.\n") if ($debug);
         my $state = $self->{current};
         $self->state0();
         $self->_printlog("comes to state: " . $self->{current} . "\n") if ($debug);
         $try-- while( $try > 0 && ! $self->_movState($state)); 
         $self->_printlog("comes to state: " . $self->{current} . "\n") if ($debug);
      }else{
         $self->_rmecho(\$msg,$cmd);
         return $msg;
      }
   }
   return undef;
}


sub _expectprint {
   my ($self,$cmd) = @_;
   $SIG{ALRM}  = sub { return undef };
   alarm($self->{timeout});
   $self->{host}->send("$cmd\n");
   $self->_printlog("send <$cmd>\n") if ($debug);
   alarm(0);
   1;
}

=head2 sendCmd($cmd, $timeout, $retry)

Send $cmd and check the echo back of $cmd
After sending $cmd, it checks the echo-back of $cmd. If it sees echo-back,
the operation is regarded as success and returns 1. Otherwise by default
it will try another time with slow speed to see if this can be done, unless
$retry is provided. If all tries failed, it die out.

This method is necessary for two reasones.
- Make sure the connection is good
- The command itself is eliminated from the output of the command.

This process can be skipped if your connection doesn't echo back command,
in such case, you must set the object attribute "noechoback";

input: $cmd - command to be executed
       $timeout - optional, default is the class's timeout, see build()
                  timeout to wait for the echo-back happens.
       $retry - optional, default is 2, the number of repeat to make it success.
=cut
 
sub sendCmd {
    my ($self, $cmd, $echo_tmout, $retry) = @_;
    my $exp = $self->{host};

    # parameters to control connection
    $retry ||= 2;
    $echo_tmout ||= $self->{timeout};
    my $retSequence = '[\r\n]+';
    my $eraseChar = "\025";

    my $i = 1;
    my $success = 0;

    $self->_printlog("<$cmd>\n");
    # if echoback incapable, igore the dectection of it.
    if ( exists $self->{noechoback} && $self->{noechoback} ) {
        $exp->send("$cmd\r");
        return 1;
    }

    $exp->send($cmd);
    
    # some device echo back full word even typed partial
    my $cmdEchoRE = $self->_echoBackRE($cmd);
    while ($i <= $retry) {
        my ($timeout,$echo_counter) = ($echo_tmout,0);
        $exp->expect($timeout,
                 [ '-re', "(.*)$cmdEchoRE\$",
                   sub {###my $fh = shift;
                        my $cr_counter = 0;
                        $self->_printlog("i see <$cmd> is echoed back\n") if ($debug);
                        $self->_printlog("sending \\r\n") if ($debug);
                        ###$fh->send("\r");
                        $exp->send("\r");
                        $exp->expect($timeout,
                        ###$fh->expect($timeout,
                                    [ '-re', "$retSequence",
                                      sub { $success = 1;
                                            $self->_printlog("retSequene is seen, done successfully\n") if ($debug);
                                          }],
                                    [ timeout =>
                                      sub { $self->_printlog("timeout, retSequene not seen\n") if ($debug);
                                            unless(++$cr_counter >= $retry) {
                                                $self->_printlog("sending \\r slowly\n") if ($debug);
                                                ###$fh->send_slow(1,"\r\r");
                                                $exp->send_slow(1,"\r\r");
                                                exp_continue;
                                            }elsif($i >= $retry) {
                                                die "has tried $retry times, give up\n";
                                            }
                                          }],
                                   );
                       }],
                 [ timeout => sub { ###my $fh = shift;
                                    $self->_printlog("timeout, <$cmd> not seen\n") if ($debug);
                                    $exp->send_slow(1,"$eraseChar");
                                    unless(++$echo_counter >= $retry) {
                                        $self->_printlog("resending <$cmd> slowly\n") if ($debug);
                                        ###$fh->send_slow(1,"$eraseChar");
                                        $exp->send_slow(1,"$cmd");
                                        ###$fh->send_slow(1,"$cmd");
                                        exp_continue;
                                    }else{
                                        die "has tried $retry times, give up\n";
                                    }
                                  }
                 ],
        );
        return $success if $success;
        $self->_printlog("resending <$cmd> slowly\n") if ($debug);
        $exp->send_slow(1,"$eraseChar");
        $exp->send_slow(1,"$cmd");
        $i++;
    }
    return $success;
}



sub _rmecho {
    my ($self,$msg,$cmd) = @_;
    $self->_printlog("<return message:>\n") if ($debug);
    $self->_printlog("<$$msg>\n") if ($debug);
    #$$msg =~ s/\r\n|\r/\n/g;
    $$msg =~ s/\r//g;
    #$$msg =~ s/\n/%/g;
    chomp $cmd;
    $$msg =~ s/^\s*\Q$cmd\E\n//;
    $self->_printlog("<after processed:>\n") if ($debug);
    $self->_printlog("<$$msg>\n") if ($debug);
}

# prevent password exposure
# my $prtout = $self->_shield($_,$pats->{$_});
sub _shield {
    my ($self,$key,$v) = @_;
    ($key =~ /passw(or)?d/i) ? '******' : $v;
}

sub _expDebugKnob {
    my ($self,$v) = @_;
    $self->{host}->exp_internal($v);
}

sub _getNofromName {
   my ($self,$name) = @_;
   my $state = $self->{state};
   for (my $i = 0; $i < @$state; $i++) {
      return $i if ($state->[$i]{name} eq "$name");
   }
   ###return undef;
   # instead, it's better to die because this always happens in development phase
   my $pkgname = ref $self;
   die "no $name state defined in " . ref($self) . "\n";
}

sub _echoBackRE {
    my ($self,$cmd) = @_;
    if ($self->{autofillup}) {
        return join '\s+', map { $_ . '\S*'} split /\s+/, $cmd;
    }else{
        $cmd =~ s/(\^|\$|\?)/\\$1/g;  # escape ^,$
        return $cmd;
    }
}
 

# goto $to state from current state, just try once
# It assumes that there is a path from current to $to defined already, otherwise use _movState.
#
# new solution to auto adapt into any state, this may happen in some scenarios.
# for example, telnet to a device, means state0->some state, for console connection
# the state is a left over from the last connection, so it may be any states.
# so the transition to any state should be a successful one.
# the expect body from current to $to is used in transition, but tolerate any stable states.
# return true : if succesfully move to any stable state, 
#        false: otherwise
sub _goState {
    my ($self,$to) = @_;
    my $final = 'false';
    $final = 'true' if ($to == 0);
    my $prompt = $self->{state}[$to]{prompt};
    my $trans = $self->{state}[$self->{current}]{trans};
    my $command = $trans->{$to}{command};
    my $expect = $trans->{$to}{expect} if (exists $trans->{$to}{expect});
    my $prompts;

    # this is $to state's prompt, should be first
    push @$prompts, $prompt;

    my $exp;
    $self->_printlog("going to send command => <$command>\n") if ($debug);

    if (exists $self->{host}) {
        $exp = $self->{host};
        # use sendCmd, so the $command is not echoed back
        # and make sure it's sent to spawned process
        if (ref $command eq 'ARRAY') {
            for (my $i = 0; $i < @$command; $i++) {
                $self->sendCmd($command->[$i]);
                # clean the buffer to make each command "separatedly" executed.
                $self->{host}->clear_accum() unless ($i == @$command - 1);
            }
        }else{
            $self->sendCmd($command);
        }
    }else{
        $exp = new Expect;
        $self->{host} = $exp;
        $exp->raw_pty($self->{expRaw});
        $exp->log_stdout($self->{liveExp});
        my $F = IO::File->new_from_fd($self->{logF},">");
        $exp->log_file($F);
        $self->_expDebugKnob($self->{debugExp});
        $exp->spawn("$command");
        $self->_printlog("spawn <$command>\n") if ($debug);
        $exp->clear_accum();
    }

    #
    # built expect body from $expect and defPattern and all states prompts
    #
    my $result;
    my $msg = "";
    my $pats;

    # A transition pattern is added or override defPattern one
    if (defined $expect) {
        #$self->_addDashr($expect); # not necessary 'cause it's done already during transitState()
        push @$pats, @$expect;
    }

    # defPattern is added, which is defined by caller for a specific class
    push @$pats, @{$self->{defPattern}};


    # Adding states prompt
    for my $state ( 0 ... scalar @{$self->{state}} - 1) {
        push @$prompts, $self->{state}[$state]{prompt};
    }

    ###my $code = $self->_buildExpBody($pats,[$prompt]);
    my $code = $self->_buildExpBody($pats,$prompts);

    eval "$code";
    $self->_printlog("expect result: <$result>\n") if ($debug);

    # goto init state may lost connection, so it's still successful.
    if ($result == 3 && $final eq 'true') {
        $self->state0;
        $result = 1;
    }
    ($result == 1) ? 1 : 0;
}

# Attention: change caller's $expect
# add a \r at end in case it's not there, except the control char or \n at end
# one instance is ^] to terminate the telnet, and "quit\n" to end the session
# those shouldn't be appended with \r to send the string/char/whatever
# [ { }, ] 
sub _addDashr {
    my ($self, $expect) = @_;
    for my $one (@$expect) {
        for (keys %$one) {
            chomp( my $act = $one->{$_});
            next if $self->isCtrlChar($act);
            next if $act =~ /\\n$/;
            $act =~ s/(\\r)?$/\\r/;
            $one->{$_} = $act;
        }
    }
}

sub isCtrlChar {
    my ($self, $act) = @_;
    return 1 if ($act =~ /\\x[01][0-9a-f]|\\x7f/); # 0 to 1f in hex. plus DEL (177)
    return 1 if ($act =~ /\\0[0-3][0-7]|\177/);   # 000 to 037 in oct. plus DEL (7f) 
    0;
}


sub _errDispatch {
   my ($self, $errmsg) = @_;

   if ($self->{errMode} eq 'die') {
      die "$errmsg\n";
   }elsif(ref($self->{errMode}) eq 'CODE') {
      &{$self->{errMode}}("$errmsg");
   }elsif(ref($self->{return}) eq 'return') {
      $self->_printlog("$errmsg\n");
      return 1;
   }
}

sub _printlog {
   my ($self,$msg) = @_;
   my $logh = $self->{logF};
   my $stamp = scalar localtime;
   $msg = "Angel<$stamp>: $msg";
   $logh->print($msg);
}

sub _prtSecWarn {
    my $self = shift;
    my $len = 50;
    print STDERR "\n\n" . '*' x $len . "*\n";
    print STDERR "*" . ' ' x ($len - 1) . "*\n";
    print STDERR "*  Warning: Password information may be printed   *\n";
    print STDERR "*           out to log in debug mode              *\n";
    print STDERR "*" . ' ' x ($len - 1) . "*\n";
    print STDERR '*' x $len . "*\n";
    print STDERR "   Are you sure to continue ?! ('yes' to continue) "; 
    chomp (my $in = <STDIN>);
    ($in =~ /yes/i) ? 1 : 0;
}

  
1;

__END__
# Below is stub documentation for your module. You'd better edit it!


=head1 See also

  Expect::Angel::Cisco
  Expect::Angel::Juniper
  Expect::Angel::Linux

=head1 Changes

 2007 verison 0.02
 2010 verison 1.00

=head1 AUTHOR

Ming Zhang E<lt>ming2004@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by ming zhang

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
