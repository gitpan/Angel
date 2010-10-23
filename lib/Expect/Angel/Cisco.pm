package Expect::Angel::Cisco;
use base Expect::Angel;
our $VERSION = '1.00';

=head1 NAME

 Expect::Angel::Cisco - Build up a robust connection to Cisco or cisco-like device


=head1 SYNOPSIS

 use Expect::Angel::Cisco;
 my $dut_ip = '10.1.1.100';
 # connects the device and goes to its enable mode
 my $dut = new Expect::Angel::Cisco(connection => "ssh $dut_ip", goto => 'enable' )
             or die "Failed to access to device\n";
 # check device's clock
 my $clock = $dut->cmdexe("show clock");

 # configure its interface eth1/1
 my @int_cmds = ("int eth1/1",
                 "ip address 10.2.1.1/24",
                 "no shut"
                );
 $dut->cmdexe(\@int_cmds, "config");

 # parse its parameters on eth1/1
 my @lines = $dut->cmdexe("show int eth1/1");
 for (@lines) {
     # parsing
 }

 # executes a list of commands at "config" mode of Cisco device
 my @cmd = ("interface e0/0",
            "ip address 10.1.1.10 255.2555.255.0",
            "no shut",
            "exit",  
            "interface e0/1",
            "ip address 10.1.2.100 255.2555.255.0",
            "no shut"
           );
 $dut->cmdexe(\@cmd, "config");

 # always stay at config mode for each command execution, although
 # existing some command that may change mode inadvertently.
 $dut->sticky(1);
 my @cmd = ("interface e0/0",
            "ip address 10.1.1.10 255.2555.255.0",
            "end",  # NOTE, this cause the transition to "enable" mode
            "interface e0/1",
            "ip address 10.1.2.100 255.2555.255.0",
            "no shut"
           );
 $dut->cmdexe(\@cmd, "config");
  

 # check if a command is rejected by device
 if ( defined (my $clock = $dut->cmdSendCheck("show clock")) ) {
     print "system current clock is \"$clock\"\n";
 }else{
     # "show clock" is rejected 
 }


=head1 Description

 This module is a derivation of Expect::Angel on Cisco-like devices. It's pretty simple 
because most of the function has been implemented in Expect::Angel. It serves more like
an example of how to use Expect::Angel to apply to Cisco device.

=head1 new()

  Create a new Cisco object 
  connection => "command to connect to Cisco device", for example telnet 1.1.1.1 3000
  hostname => hostname_of_Cisco, it should be switch's host name. It will be used in prompt 
              pattern match. If not specified, it's ignored at prompt match, but risky.

  # user/passwd/enablePass, if not provided, will be prompted to input from keyboard
  user     => username, used to access the device.
  passwd   => password, used to access the device.
  enablePass  => password, used to access the enable mode.
  goto => enable|config, optional. Will go to that state (mode) if specified.
  see Angel's build method for all other options.

  This is a good example to show how to build a module by means of Expect::Angel.
  Different type of devices may have slight difference in their state transition.
  You can modify it accordingly to fit your specific device. The major methods are
  inherited from Expect::Angel.
  
=cut

sub new {
     my $type = shift;
     my $para = {@_};

     # default pattern is always added into Expect body. 
     my $defPats = [{ '[-]+\s*(More|more)\s*[-]+' => ' ',
                     '^.* memory\? *\[confirm\] *$' => '\r',
                     '^.*Are you sure\?.*\[confirm\] *$' => '\r',
                     '^.*Are you sure\?.*$'              => 'yes\r',
                     '^.*Are you sure you want to continue connecting\?.*$' => 'yes\r',
                     'Escape character is \\\'\^\]\\\'\.' => '\r',
                   }];

     $para->{defPattern} = $defPats;
     $para->{aggressive} = 1;
     my $conn = $type->build(%$para);
     
     # hostname is used at prompt match, it should be switch's host name.
     # if not specified, it's ignored at prompt match, but risky.
     my $hostname = (exists $para->{hostname}) ? $para->{hostname} : '';

     #
     # define states
     #   1 - rommon
     #   2 - non privilege
     #   3 - enable
     #   4 - config
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
     $conn->addState(%$_) for (@$states);

     #
     # check if credential is provided, otherwise read from keyboard
     #
     $para->{user} = $conn->getUsername() unless(defined $para->{user});
     $para->{passwd} = $conn->getPasswd("Password:") unless(defined $para->{passwd});
     $para->{enablePass} = $conn->getPasswd("enable password:") unless(defined $para->{enablePass});

     #
     # define transition
     #

     # 0 -> 1 
     $trans = {nexthop => 2};
     $conn->transitState(0,1,$trans);

     # 0 -> 2, 0 -> 3 
     # right after telnet or ssh to a device, it's at 2 or 3
     my $trans = { command => $para->{connection},
                   expect => [{ 'Username: \r?$' => "$para->{user}",
                                  'login: \r?$' => "$para->{user}",
                                  'Login: \r?$' => "$para->{user}",
                               'Password: \r?$' => "$para->{passwd}",
                               'password: \r?$' => "$para->{passwd}"}]
                 };
     $conn->transitState(0,2,$trans);
     $conn->transitState(0,3,$trans);

     # 1 -> 2
     # at rommon mode, boot can go to 2.
     $trans = {command => "boot"};
     $conn->transitState(1,2,$trans);

     # 2 -> 3 
     $trans = { command => "enable",
                expect => [{ 'Password: \r?$' => "$para->{enablePass}"}]
              };
     $conn->transitState(2,3,$trans);

     # 3 -> 4 
     $trans = {command => "config t" };
     $conn->transitState(3,4,$trans);

     # 4 -> 3 
     #$trans = {command => "end", expect => { } };
     $trans = {command => "end" };
     $conn->transitState(4,3,$trans);

     # 3 -> 2
     $trans = {command => "exit" };
     $conn->transitState(3,2,$trans);

     #3 -> 0, 2 -> 0
     $trans = {command => "exit",
               expect => [{ 'telnet> \r?$' => 'quit\n' },
                          {'.+' => '\x1d' }
                          #{'.+' => '\035' }
                         ]
              };
     $conn->transitState(3,0,$trans);
     $conn->transitState(2,0,$trans);

     # 
     # transit to the specified state
     #
     if (exists $para->{'goto'}) {
        return $conn->movState($para->{'goto'}) ? $conn : undef;
     }
     $conn;
}


=head1 enableMode()

  transits to enable state. It will try 3 times (defined by errTries)
  input: none
  output: true - the state is transitted to enable state
          undef - can not transit to enable state

=cut

sub enableMode {
     my ($conn) = shift;
     $conn->movState("enable") or return undef;
}
  
=head1 configMode()

  transits to config state. It will try 3 times (defined by errTries)
  input: none
  output: true - the state is transitted to config state
          undef - can not transit to config state

=cut

sub configMode {
     my ($conn) = shift;
     $conn->movState("config") or return undef;
}

=head1 cmdexe(cmd,expect,state)

   Inherited from Expect::Angel, refer to it for detail

=cut

=head1 cmdSendCheck($cmd,$errorPattern)

 This sub will exectues $cmd at current state and detect if $errorPattern 
 matches its output in the each execution. 
 If the command is rejected, it will return immediatedly.
 $cmd: single or ref to a list of commands
 $errorPattern: optional, RE of error pattern, default is '^%|Invalid command'
 return: undef when $errorPattern matches, otherwise output of the last command

=cut

sub cmdSendCheck {
    my ($self, $cmd,$errorPattern) = @_;
    $errorPattern ||= '^%|Invalid command';
    $self->SUPER::cmdSendCheck($cmd,$errorPattern);
}


=head1 bye()

  Close the connection decently

=cut

sub bye {
    my ($conn) = shift;
    $conn->movState(0) or return undef;
}
  
=head1 pingable($ip_addr) 

 Test if target $ip_addr is reachable from the DUT by ping it.
 Input: $ip_addr - ip address of target 
 Return: number of echoback packats, all parameters are device default.
        so it will be 5 if 100% success.

=cut

#  Sending 5, 100-byte ICMP Echos to 10.129.144.1, timeout is 2 seconds:
## !!!!!
#  Success rate is 100.0 percent (5/5), round-trip min/avg/max = 0/3/16 (ms)
#  Sending 5, 100-byte ICMP Echos to 10.10.101.111, timeout is 2 seconds:
#  .....
#  Success rate is  0.0 percent (0/5)

sub pingable {
    my ($conn,$ip_addr) = @_;
    my $success;
    my $expBody = [{
                    'Target IP address or host   : ' => "$ip_addr",
                    'Repeat Count \[5\]    : ?'     => '', 
                    'Datagram size \[100\] : ?'     => '',
                    'Timeout in secs \[2\] : ?'     => '',
                    'Extended commands \[n\] : ?'   => '',
                    'Sweep range of sizes \[n\]: ?' => '',
                  }];
    for ( $conn->cmdexe("ping",$expBody,"enable") ) {
        next unless ( /^\!|\.$/ );
        $success = grep { $_ eq '!' } split '', $_;
    }
    return $success;
}

1;

