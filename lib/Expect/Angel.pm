package Expect::Angel;

use 5.008005;
use strict;
use warnings;
our $VERSION = '0.02';
use Expect;
my $debug = 0;

# constructor
sub build {
   my $type = shift;
   my $self = { @_ };
   bless $self, $type;
   $self->{current} = 0;
   #
   # error handling
   #
   $self->{errTries} ||= 3;
   $self->{errMode} ||= 'die';
   $self->{timeout} ||= 30;
   $debug = $self->{debug} if (exists $self->{debug});
   delete $self->{aggressive} unless(exists $self->{aggressive} && ! $self->{aggressive});

   #
   # log
   #
   if (exists $self->{log} && ref $self->{log} eq 'GLOB') {
      $self->{logF} = $self->{log};
   }else{
      my $logfile = "angel.log";
      $logfile = $self->{log} if (exists $self->{log});
      open LOGFILE, ">>$logfile" or die "can not open $logfile\n";
      $self->{logF} = \*LOGFILE;
      print LOGFILE "\n=== Angel(author:Ming Zhang) is serving ====\n\n";
   }

   my %init = map { $_ => $self->{$_} } grep { /^name|descr|prompt$/ } keys %$self;
   $self->addState(%init);
   return $self;
}

sub addState {
   my $self = shift;
   my $mode = {@_};
   $self->{state} = [] unless(exists $self->{state});
   my $no = @{$self->{state}};
   for (qw(name descr prompt)) {
      $mode->{$_} = "state".$no unless(exists $mode->{$_});
   }
   if ($no == 0) {
      $mode->{descr} = 'initial state';
      $mode->{prompt} = 'null';
   }
   push @{$self->{state}}, $mode;
   return @{$self->{state}} - 1;
}

sub transitState {
   my ($self,$from,$to,$trans) = @_;
   my $msg = "$from and/or $to not found";
   $from = $self->_getNofromName($from) unless ($from =~ /^\d+$/);
   $to = $self->_getNofromName($to) unless ($to =~ /^\d+$/);
   die "\n$msg\n" unless(defined $from and defined $to);
   my $old = $self->{state}[$from]{trans}{$to} if (exists $self->{state}[$from]{trans}{$to});
   $self->{state}[$from]{trans}{$to} = $trans;
   (defined $old) ? $old : undef;
}

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
            print "\tcommand => $para->{command}\n";
            for (keys %{$para->{expect}}) { print "\twhen see <$_> => send <$para->{expect}{$_}>\n" };
         }else{
            for (keys %$para) { print "\t$_ => $para->{$_}\n" };
         }
      }
   }
   print "===== End of Report ====\n\n";
}

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

# return true if succesfully move to the state
sub _movState {
   my ($self,$to) = @_;
   my $nexthop;
   my $errMsg = "can not find the name $to";
   $to = $self->_getNofromName($to) unless ($to =~ /^\d+$/);
   die "\n$errMsg\n" unless(defined $to);
   return 1 if ($self->{current} == $to);
   print "\ngoing to state $to\n" if ($debug);
   my $final = 'false';
   $final = 'true' if ($to == 0);
   my $prompt = $self->{state}[$to]{prompt};
   my $trans = $self->{state}[$self->{current}]{trans};
   if (defined $trans->{$to}) {
      if (exists $trans->{$to}{nexthop}) {
         $self->_movState($trans->{$to}{nexthop}) or return undef;
      }else{
         my $command = $trans->{$to}{command};
         my $expect = $trans->{$to}{expect};
         if ($self->_goState($prompt,$command,$expect,$final)) {
            $self->{current} = $to;
         }else{
            return undef;
         }
      }
   }elsif($to > $self->{current} + 1) {
      $nexthop = $self->{current} + 1;
      $nexthop = $to - 1 if ($self->{aggressive});
      $self->_movState($nexthop) or return undef;
   }elsif($to < $self->{current} - 1) {
      $nexthop = $self->{current} - 1;
      $nexthop = $to + 1 if ($self->{aggressive});
      $self->_movState($nexthop) or return undef;
   }else{
      die "\n$to has not defined at current state $self->{current}\n";
   }
   $self->_movState($to) or return undef unless($self->{current} == $to);
}

sub state0 {
   my ($self) = @_;
   $self->{current} = 0;
   $self->{host}->soft_close();
   print "back to initial state 0\n" if ($debug);
   delete ($self->{host});
}

sub echo {
   my ($self, $cmd, $expect) = @_;
   my @feedback = ();
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


sub _expectecho {
   my ($self, $cmd, $expect) = @_;
   $self->{host}->clear_accum();
   my $logh = $self->{logF};
   my $try = $self->{errTries};
   while ($try-- > 0) {
      my $err = 0;
      my $msg = "";
      unless(defined $self->_expectprint("$cmd")) {
         $@ = "print to a dead IO";
         print "print to a dead IO" if ($debug);
         $err = 1;
      }elsif($expect) {
         my $status = 0;
         my $prompt = $self->{state}[$self->{current}]{prompt};
         if ($debug) {
            print "going to\n\tsend command => <$cmd>\n";
            print "\texpecting $_ => $expect->{$_}\n" for (keys %$expect);
            print "\tuntil prompt => <$prompt>\n";
         }
         my $result;
         my $code = '$self->{host}->expect($self->{timeout},'."\n";
         for (keys %$expect) {
            if ($debug) {
               $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$msg .= \$fh->before().\$fh->match(); \$fh->send(\"$expect->{$_}\\n\"); print \$logh 'see <$_> input <$expect->{$_}>'\.\"\\n\";print 'see <$_> input <$expect->{$_}>'\.\"\\n\" ; exp_continue; } ],\n";
            }else{
               $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$msg .= \$fh->before().\$fh->match(); \$fh->send(\"$expect->{$_}\\n\"); print \$logh 'see <$_> input <$expect->{$_}>'\.\"\\n\"; exp_continue; } ],\n";
            }   
         }   
         $code .= "\t[ '-re', \'$prompt\', sub { my \$fh = shift; \$msg .= \$fh->before(); \$result = 1; print \$logh \"see current prompt <\$prompt>\"\.\"\\n\"; } ],\n";
         $code .= "\t[ eof => sub { \$result = 3; print \$logh \"end-of-file\\n\";} ],\n";
         $code .= "\t[ timeout => sub { \$result = 2;  print \$logh \"timeout\\n\"; } ],\n";
         $code .= ");\n\n";
         print "\n\tby executing ...\n\n$code\n" if ($debug);
         eval "$code";
         print "expect result: <$result>\n" if ($debug);
         $err = ($result == 1) ? 0 : 1;
      }else{
         my $result;
         $self->{host}->expect($self->{timeout},
                              [ '-re', '--\s*(More|more)\s*--', sub { $msg .= $self->{host}->before(); my $fh = shift; $fh->send(" "); exp_continue;}],
                              [ '-re',"$self->{state}[$self->{current}]{prompt}",sub { $msg .= $self->{host}->before(); print $logh "see current prompt <$self->{state}[$self->{current}]{prompt}>\n"; $result = 1; } ],
                              [ eof => sub { print $logh "end-of-file\n"; $result = 3; } ],
                              [ timeout => sub { print $logh "timeout\n"; $result = 2; } ]);
         if ($result != 1) {
            $@ = "Never got response of \"$cmd\"";
            $err = 1;
         }
      }
      if ($err) {
         print "$@, reconnect again.\n" if ($debug);
         my $state = $self->{current};
         $self->state0();
         print "comes to state: " . $self->{current} . "\n" if ($debug);
         $try-- while( $try > 0 && ! $self->_movState($state)); ### or return undef;
         print "comes to state: " . $self->{current} . "\n" if ($debug);
      }else{
         $self->_rmecho(\$msg,$cmd);
         return $msg;
      }
   }
   return undef;
}

sub _expectprint {
   my ($self,$cmd) = @_;
   my $fh = $self->{logF};
   $SIG{ALRM}  = sub { return undef };
   alarm($self->{timeout});
   $self->{host}->send("$cmd\n");
   print "send <$cmd>\n" if ($debug);
   print $fh "send <$cmd>\n";
   alarm(0);
   1;
}

sub _rmecho {
    my ($self,$msg,$cmd) = @_;
    print "<return message:>\n" if ($debug);
    print "<$$msg>\n" if ($debug);
    $$msg =~ s/\r\n|\r/\n/g;
    chomp $cmd;
    $$msg =~ s/^\s*\Q$cmd\E\n//;
    print "<after processed:>\n" if ($debug);
    print "<$$msg>\n" if ($debug);
}


sub _getNofromName {
   my ($self,$name) = @_;
   my $state = $self->{state};
   for (my $i = 0; $i < @$state; $i++) {
      return $i if ($state->[$i]{name} eq "$name");
   }
   return undef;
}


sub _goState {
   my ($self,$prompt,$command,$expect,$final) = @_;
   my $logh = $self->{logF};
   if ($debug) {
      print "going to:\n\tsend command => <$command>\n";
      print "\texpecting $_ => $expect->{$_}\n" for (keys %$expect);
      print "\tuntil prompt => <$prompt>\n";
   }
   my $exp;
   if (exists $self->{host}) {
      $exp = $self->{host};
      $exp->send("$command\n");
      print $logh "send <$command>\n";
      print "send <$command>\n" if ($debug);
   }else{
      $exp = new Expect;
      $exp->raw_pty(1);
      $exp->log_stdout(0);
      $exp->log_file("./logfile");
      ###$exp->debug(1);
      $exp->spawn("$command");
      print $logh "send <$command>\n";
      print "send <$command>\n" if ($debug);
      $exp->clear_accum();
      $self->{host} = $exp;
   }
   my $result;
   my $code = '$exp->expect($self->{timeout},'."\n";
   for (keys %$expect) {
      if ($debug) {
         $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$fh->send(\"$expect->{$_}\\n\"); print 'see <$_> input <$expect->{$_}>'\.\"\\n\";print \$logh 'see <$_> input <$expect->{$_}>'\.\"\\n\"; exp_continue; } ],\n";  ### \r or \n
      }else{
         $code .= "\t[ '-re', \'$_\', sub { my \$fh = shift; \$fh->send(\"$expect->{$_}\\n\"); print \$logh 'see <$_> input <$expect->{$_}>'\.\"\\n\"; exp_continue; } ],\n";
      }   
   }   
   $code .= "\t[ '-re', \'$prompt\', sub { print \$logh \"see prompt <\$prompt>\"\.\"\\n\"; \$result = 1; } ],\n";
   $code .= "\t[ eof => sub { \$result = 3; print \$logh \"end-of-file\\n\"; } ],\n";
   $code .= "\t[ timeout => sub { \$result = 2; print \$logh \"timeout\\n\"; } ],\n";
   $code .= ");\n\n";
   if ($debug) {
      print "\n\tby executing ...\n\n";
      print "$code\n";
   }
   eval "$code";
   print "expect result: <$result>\n" if ($debug);
   $self->state0 if ($result == 3 && $final eq 'true');
   ($result == 1 || ($result == 3 && $final eq 'true')) ? 1 : 0;
}

sub _errDispatch {
   my ($self, $errmsg) = @_;

   if ($self->{errMode} eq 'die') {
      die "$errmsg\n";
   }elsif(ref($self->{errMode}) eq 'CODE') {
      &{$self->{errMode}}("$errmsg");
   }elsif(ref($self->{return}) eq 'return') {
      print "$errmsg\n";
   }
}

1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Expect::Angel - Build up a robust connection to your DUT

=head1 SYNOPSIS

  use Expect::Angel;
  @ISA = ("Expect::Angel");
  sub new {
     my $type = shift;
     my $para = {@_};
     my $conn = $type->build(%$para);
     blah blah blah
  }

=head1 DESCRIPTION

If you are looking for a module that can help quickly build up a robust connection to your DUT, then here is the right place!

Angel is just like a messenger between your testing machine, where everyting is perfect like heaven, and DUT (device under test), where exists right and wrong like earth. The messenger must tolerate the errors and disasters occuring on DUT and faithful deliver information to and from the DUT.

Angel is built on Expect.pm module, but hides the complexity of it. With Angel.pm You can easily build an object-oriented module that meets your specific need with the most useful methods inherited from Angel.

Let's take CISCO router as the first example, and I will show another one that simulates a complex DUT scenarios with Linux machine in the package.

 CISCIO Router

 Modes:  Non-privilege  --- (enable) ---> Enable Mode -- (config t) --> Config Mode

                        <-- (exit) ------             <-- (exit) -----

Here the router has 3 modes, Non-privilege, Enable, and Config. When executing enable command at 1st mode, it transits to Enable mode, and so on as shown.


General speaking, DUT is a network appliance that provides CLI (command line interface) for user to configure and manupulate. It's very ofter that a DUT presents multiple states, each grants a level of privileges.

  DUT:    state0  ---->  state1  ----->  state2 ... ... -----> stateN   
                  <----          <-----                 <-----

Each state is a stable mode of the DUT, at which the DUT may accept an input and execute it as a command.
Each state has its own prompt and a set of commands appropriate to this state. The commands under a state can be put into categories.

1. After execution the state keeps the same. 
2. After execution the state transits to another one. 
3. The execution will show more prompt asking for more input, and eventually back to the same state.

The state transition may happen between two adjacent states, or skip some states.

Your task is to tell Angel the following information for a specific DUT. 
1. describes the states and their prompts
2. describes the state transition

Angel provides you: 
1. Maintain the connection to DUT.
2. Send command to DUT at each state and retrieve response of the command.
3. Error handling.
4. Log the messages exchanged.

 Properties to the connection to DUT (common to all states):
 -  timeout  => seconds,  
 -  errTries => times to try on error,
 -  errMode  => return|die|code,
 -  log      => file_name or File_handle.
    The messages exchanged will be written to the file specified by file_name, or File_handle if you have your own log framework. If none is seen, "angel.log" at current directory is the target. 

 - aggressive
   This controls the state transition behavior.
  . right direction decision
     if defined, try to move directly
     otherwise, try one hop backward of the target
     for example, current state = 1, target state = 4
                  if defined trans to state 4, then go directly;
                  otherwise, check if trans to state 3 defined;
                  if not, then try state 2, and so on.
     As long as there is a path defined from source state to target state, it can try

  . left direction,
     similiar to right direction
  
  The default behavior is non-aggressive, which tries one hop forward from the source,
  i.e. if 1 to 4 fails, it tries to go to 2 first, then 2 to 4.

 Properites of a state
   descr: description of this state, used for human readable purpose only.
   name: name of the state, unique in all states, numbers only is not allowed to avoid ambiguous with default states, which are 0, 1, 2, etc. State is identified by either the sequence number (0 is the initial state), or the name.
  prompt: prompt of this state, in perl regular expression
  trans: transition method and parameters

  -- state_transition_parameters
  { command => "executable command at the state",
    expect => { hint/answer block }
  }

  -- hint/answer bloc
  # if omitted, assume can expect that state after entering command
  hint => reg(RE);  # regular expression for system response to go to that state
                    # password is one example
  answer => "answer to the hint in order to go that state"

    or

  { nexthop => state_name or number }

  They are mutual exclusive. If both exists, nexthop will take precedence, i.e, try to
  go to the state first, then make follow whatever defined at that state.


=head2 Methods for Module build-up

  - build({timeout => $in_seconds, errMode => 'die|return', errTries => $number,
           goto => $state, debug => 0})

    function: create the DUT object and goto $state,
    default timeout is 30 seconds. Default errTries is 3 times. Default errMode is die.
    default state is 0, default debug is 0. You may turn it to 1 when you debug your module.

  - addState({name => $name, descr => $description, prompt => $prompt})

    add a state to DUT object
    "name" and "descr" are recommanded, default is stateN (N is incremented from existing state)
    "prompt" is a Perl regular expression for this state.

  - transitState(from, to, trans_descr)
    define how to transit states.

    from/to, if number, assume it's sequence number of the state, otherwise, it's name of the state.
    trans_descr, ref to a state_transition_parameters block

  - catState
    print all the defined states for debug


  - movState($to)
    do state transition from one state to another. if failed, it will try errTries times (defualt is 3), each time it moves state back to 0, and goes to the target. If errTries times  has been tried and still failed, it keeps the best try state and return undef. 

  - state0
    close the socket and set the object to initial state. It doesn't try to go over the state transition from current to 0 like movState(0) does, instead, it directly calls soft_close() of Expect to close the connection.
    But it keeps all the object properties and state transition date, so it helps to re-transit to a state from initial in case it has experienced a problem in previous attempt.   If a decent goodbye is required, movState(0) is the best solution.

  - echo($cmd)
  - echo($cmd,$expect)
    This is the most frequently used method. It executes $cmd at current state, and return the response of DUT in either array, or ref of the array. It always expects current prompt after executes $cmd. An exception is that '--More--' is tolerated and SPACE is sent in response to it.
    some $cmd need to interact with DUT in terms that DUT waits for some input after accepting $cmd. Multiple prompt phrases and answers may be exchanged before the $cmd is done and final prompt shows up.
  $expect defines these interactive exchanges
  {"prompt phrase1 => answer1", ... , "prompt phraseN => answerN"}
  where "prompt phraseN" can be expressed in Regular Expression

   in case error happens when $cmd is executed, it will try errTries times (defualt is 3), each time it moves state back to 0, and goes to current state, and executes the $cmd again. If errTries times  has been tried and still failed, it takes action defined by errMode, i.e, die, return, or exectues a code, then return false condition.

   The response from the execution of the command $cmd is returned, each line is an element. Depending on the context to assign, it either returns reference or the list itself.

   # this will return a list and assigned to @msg;
   @msg = $conn->echo("ls -l");

   # this will return ref to a list and assigned to $msg;
   $msg = $conn->echo("ls -l");


  - robustecho($cmd,$retMsgPt,$rejectPattern)
    send an command to DUT may encounter 3 situations
    1. the command is slurped by DUT without rejection, the action success.
    2. the command is rejected by DUT with error message, the action is failed
    3. DUT is crashed by the command, the action cause catastrophe

    This method detects the situation and return true on No.1, false on No.2, and undef on No.3
    $retMsgPt is a ref to list, the response of DUT to $cmd is assiged to it.
    $rejectPattern is RE that tells the matched response is regarded as rejection message from DUT.
    If the No.3 happens, $retMsgPt will hold the error message.


=head1 Examples

Example 1: Cisco router module

  package Cisco;
  use Expect::Angel;
  @ISA = ("Expect::Angel");
  my $debug = 0;
  #
  sub new {
     my $type = shift;
     my $para = {@_};
     my $conn = $type->build(%$para);

     #
     # define states
     #
     my $states = [( { prompt => 'router>$' },  # state 0
                   { prompt => 'router#$',    # state 1
                     name   => "enable",         
                     descr  => "enable mode"
                   },
                   { prompt => 'router\(config\)#$',   # state 2
                     name   => "config",
                     descr  => "configuration model"
                   },
                )];
     $conn->addState(%$_) for (@$states);

     #
     # define transition
     #
     # 0 -> 1
     my $trans = {command => "telnet $para->{dut}",
                expect => { 'Username: \r?$' => $para->{user},
                            'Password: \r?$' => $para->{passwd} }
               };
     $conn->transitState(0,1,$trans);

     # 1 -> 2 
     $trans = {command => "enable",
                expect => { 'Password: \r?$' => $para->{enpasswd} }
               };
     $conn->transitState(1,2,$trans);

     # 2 -> 3 
     $trans = {command => "conf t", expect => { } };
     $conn->transitState(2,3,$trans);

     # 3 -> 2 , 2 -> 0
     $trans = {command => "exit", expect => { } };
     $conn->transitState(3,2,$trans);
     $conn->transitState(2,0,$trans);

     # 2 -> 1 
     $trans = {nexthop => 0 };
     $conn->transitState(2,1,$trans);
  
     # 
     # transit to the specified state
     #
     if (exists $para->{'goto'}) {
        return $conn->movState($para->{'goto'}) ? $conn : undef;
     }
     $conn;
  }

  sub enableMode {
     my ($conn) = shift;
     $conn->movState("enable") or return undef;
     # or if you prefer to use state number
     # $conn->movState(2) or return undef;
  }
  
  sub confMode {
     my ($conn) = shift;
     $conn->movState("config") or return undef;
  }
  
  1;
  
There is the script to test the model

  #!/usr/bin/perl -w
  use Expect::Angel;
  use lib(".");
  use Cisco;
  
  my $m = '10.1.1.1';
  our $dut = new Cisco(user => 'username', passwd => 'your_passwd', enpasswd => 'en_passwd', dut => $m ) or die "Failed to connect to $m\n";
  
  for $s1 ( 1 ... 3 ) {
     $dut->movState($s1) or die "\nfailed to back from $s2 to state $s1\n\n";
     for $s2 (1,2,3) {
        if ($dut->movState($s2)) {
           print "success from $s1 to $s2\n";
        }else{
           print "failed from $s1 to $s2\n";
           print "current state: $dut->{current}\n";
        }
     }
  }
  $dut->enableMode() or die "failed to go to enable mode\n";
  $dut->confMode() or die "failed to go to enable mode\n";

=head1 AUTHOR

Ming Zhang E<lt>ming2004@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by ming

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
