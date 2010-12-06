package Expect::Angel::Juniper;
use base Expect::Angel;
our $VERSION = '1.01';

=head1 NAME

Expect::Angel::Juniper - Build up a robust connection to Juniper device

=head1 SYNOPSIS

 use Expect::Angel::Juniper;
 my $connectCmd = "ssh 10.1.1.1";
 my $dut = new Expect::Angel::Juniper(connection => "$connectCmd", goto => 'operation' )
             or die "Failed to access to device by running '$connectCmd'\n";


=head1 Description

 This module is a derivation of Expect::Angel on Juniper Juno devices. It's pretty simple 
because most of the function has been implemented in Expect::Angel. It serves more like
an example of how to use Expect::Angel to apply to Juno OS device.

=head2 new()

  Create a new Juniper object 
  connection => "command to connect to Juniper device", for example telnet 1.1.1.1 3000
  hostname => hostname_of_Juniper, it should be device's host name. It will be used in prompt 
              pattern match. If not specified, it's ignored at prompt match.

  # user/passwd/configPass, if not provided, will be prompted to input from keyboard
  user     => username, used to access the device.
  passwd   => password, used to access the device.
  configPass  => password, used to access the configuration mode.

  goto => operation|config, optional. Will go to that state (mode) if specified.

  see Angel's build method for all other options.

=cut

sub new {
     my $type = shift;
     my $para = {@_};
     my $defPats = [{ '[-]+\s*\((More|more).*\)\s*[-]+' => ' ',
                     '^.* memory\? *\[confirm\] *$' => '\r',
                     '^.*Are you sure\?.*\[confirm\] *$' => '\r',
                     '^.*Are you sure\?.*$'              => 'yes\r',
                     '^.*Are you sure you want to continue connecting\?.*$' => 'yes\r',
                   }];

     $para->{defPattern} = $defPats;
     $para->{aggressive} = 1;
     $para->{autofillup} = 1;  # command echoed fully back behavior.
     my $conn = $type->build(%$para);
     
     # hostname is used at prompt match, it should be device's host name.
     # if not not specified, any would match
     my $hostname = (exists $para->{hostname}) ? uc $para->{hostname} : '.+';

     #
     # check if credential is provided, otherwise read from keyboard
     #
     #$para->{sshphrase} = $conn->getPasswd("SSH phrase:") unless(defined $para->{sshphrase});
     $para->{user} = $conn->getUsername() unless(defined $para->{user});
     $para->{passwd} = $conn->getPasswd("Password:") unless(defined $para->{passwd});
     $para->{configPass} = $conn->getPasswd("config password:") unless(defined $para->{configPass});

     #
     # user@host
     #
     my $prompt_kw = "$para->{user}\@$hostname";
     #
     # define states
     #   1 - operation
     #   2 - configure
     my $states = [( 
                   { prompt => "$prompt_kw> ?\$",    # state 1
                     name   => "operation",         
                     descr  => "operational mode"
                   },
                   { prompt => "$prompt_kw# ?\$",    # state 2
                     name   => "config",         
                     descr  => "configuration mode"
                   },
                )];
     $conn->addState(%$_) for (@$states);

     #
     # define transition
     #

     # 0 -> 1, 0 -> 2
     # connection => "ssh tftp1.ops.iso.test.sp2 ssh -c \"ulimit -H -t 10 ; telnet 10.129.160.247\"",
     my $trans = { command => $para->{connection},
                   expect => [{ 'Username: \r?$' => "$para->{user}",
                                  'login: \r?$' => "$para->{user}",
                                  'Login: \r?$' => "$para->{user}",
                               'Password: \r?$' => "$para->{passwd}",
                               'password: \r?$' => "$para->{passwd}"}]
                 };
     $conn->transitState(0,1,$trans);
     $conn->transitState(0,2,$trans);

     # 1 -> 2 
     $trans = { command => "config",
                expect => [{ 'Password: \r?$' => "$para->{configPass}"}]
              };
     $conn->transitState(1,2,$trans);

     # 2 -> 1
     #$trans = {command => [qw(top exit)], expect => { } };
     $trans = {command => [qw(top exit)] };
     $conn->transitState(2,1,$trans);

     # 1 -> 0
     #$trans = {command => "exit", expect => { } };
     $trans = {command => "exit" };
     $conn->transitState(1,0,$trans);

     # 
     # states are defined, now check it.
     #

     # 
     # transit to the specified state
     #
     if (exists $para->{'goto'}) {
        return $conn->movState($para->{'goto'}) ? $conn : undef;
     }
     $conn;
}

=head2 operMode()

  Transits to operational mode. It will try 3 times (defined by errTries)
  input: none
  output: true - the state is transitted to operational mode
          undef - can not transit to operational mode
=cut

sub operMode {
     my ($conn) = shift;
     $conn->movState("operation") or return undef;
}
  
=head2 configMode()

  Transits to config state. It will try 3 times (defined by errTries)
  input: none
  output: true - the state is transitted to config state
          undef - can not transit to config state
=cut

sub configMode {
     my ($conn) = shift;
     $conn->movState("config") or return undef;
}

=head2 bye()

  Close the connection decently

=cut

sub bye {
     my ($conn) = shift;
     $conn->movState(0) or return undef;
}

=head1 AUTHOR

Ming Zhang <ming2004@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010, Yahoo! Inc. All rights reserved.

Artistic License 1.0

=cut

  
1;

