package Expect::Angel::Linux;
use base Expect::Angel;
our $VERSION = '1.00';

=head1 NAME

Expect::Angel::Linux - Build up a robust connection to Lunix/Unix host

=head1 SYNOPSIS

 use Expect::Angel::Linux;
 my $dut = new Expect::Angel::Linux(connection => "ssh $host", liveExp => 1)
             or die "Failed to access to device by running '$connectCmd'\n";


=head2 new()

  Create a new object 
  connection => "command to connect to the host", for example telnet 1.1.1.1 3000

  echodetect => 1, see login() why you might want to set it.
  see Angel's build method for all other options.

=cut

sub new {
     my $type = shift;
     my $para = {@_};
     my $defPats = [{ '^.*Are you sure\?.*\[confirm\] *$' => '\r',
                     '^.*Are you sure\?.*$'              => 'yes\r',
                     '^.*Are you sure you want to continue connecting\??.*$' => 'yes\r',
                   }];

     $para->{defPattern} = $defPats;
     $para->{aggressive} = 1;

     # unless echodetect is set
     $para->{noechoback} = (exists $para->{echodetect} && $para->{echodetect}) ? 0 : 1;

     chomp ($para->{connection} = `which bash`) if ( $para->{connection} eq 'localhost' );
     my $conn = $type->build(%$para);
     
     #
     # define states
     #   1 - shell
     my $states = [( 
                   { prompt => '[#$%>] ?$',       # state 1
                     name   => "login",         
                     descr  => "shell on remote"
                   },
                )];
     $conn->addState(%$_) for (@$states);

     #
     # check if credential is provided, otherwise read from keyboard
     # user may be avaiable from system call getpwuid
     #
     (defined $para->{user}) or $para->{user} = getpwuid($>) or $para->{user} = $conn->getUsername();
     $para->{passwd} = $conn->getPasswd("Password:") unless(defined $para->{passwd});
     $para->{sshphrase} = $para->{passwd};
     # add them as the properties of the object
     $conn->{user} = $para->{user};
     $conn->{passwd} = $para->{passwd};

     my $authExpect = { 'Username: ?\r?$' => "$para->{user}",
                            'login: ?\r?$' => "$para->{user}",
                            'Login: ?\r?$' => "$para->{user}",
                         'Password: ?\r?$' => "$para->{passwd}",
                         'sshphrase:\r?$' => "$para->{sshphrase}",
                         'password: ?\r?$' => "$para->{passwd}"
                      };

     push @{$conn->{defPattern}}, $authExpect;

     #
     # define transition
     #

     # 0 -> 1
     # connection => "ssh tftp1.ops.iso.test.sp2 ssh -c \"ulimit -H -t 10 ; telnet 10.129.160.247\"",
     my $trans = { command => $para->{connection},
                   expect => [($authExpect)]
                 };
     $conn->transitState(0,1,$trans);

     # 1 -> 0,
     $trans = {command => "exit" };
     $conn->transitState(1,0,$trans);


     # 
     # transit to the specified state
     #
     if (exists $para->{'login'} and $para->{'login'}) {
         $conn->login() or return undef;
     }
     $conn;
}

=head2 login()

Executes the connection command and expect the shell prompt. If this is done,
it tries if the echo back is supported when raw terminial is set. Linux is not
like Cisco/Juniper routers that echo back the commands. Linux host may depend
on some configuration. If you are not sure about this, you can enable the 
auto-detect by set "echodetect => 1" in new() call. User may feel a delay in 
this auto-detection process.

input: none
output: true - success
          undef - fail
=cut

sub login {
    my ($conn) = shift;
    $conn->movState("login") or return undef;
    $conn->{state}[1]{prompt} = 'MYCOOLCONNECTION> ?$';

    if (exists $conn->{echodetect} && $conn->{echodetect}) {
        # Not sure ssh does echo command like Cisco/Juniper device
        # but raw is still highly demanded, don't do $para->{expRaw} = 0;
        # let's detect it
        my $echoTimeout = 10;
        print STDERR "\ndetecting echo back for $echoTimeout seconds, patient ...\n";
        eval { $conn->sendCmd("CANNEVERBEALEGALCOMMANDHAHABLAR", $echoTimeout, 1) };
        $conn->{noechoback} = ($@) ? 1 : 0;
    }
    $conn->cmdexe('PS1="MYCOOLCONNECTION> "');
    return 1;
}


=head2 cmdexe($cmd,$expect)

   Run a command(s), see Expect::Angel for detail

=head3 Usage
   my $output = $host->cmdexe("cat ~/myfile");
   my @output = $host->cmdexe("cat ~/myfile");

=head3 Inputs

=over

=item $cmd

 The shell command to execute on remote host

=item $expect

 Optional, ref to list of hash that describes the interactive expect body for this command.

=back

=head3 Returns

 the output of the last command execution.
 In list context it returns line by line, without \n, 
 in scalar context, it returns the string of the output.

=cut

sub cmdexe  {
    my ($self, $cmd, $expect) = @_;
    # escape single quote if any
    $cmd =~ s/'/'\\''/g;
    $self->SUPER::cmdexe($cmd,$expect);
}

=head2 cmdexe_nonesc($cmd,$expect)

Same as cmdexe() except that it does not escape single quote.
If you have a sngle quote in $comd, you mean it's used in shell command format, so it's not escaped.

=cut

sub cmdexe_nonesc  {
    my ($self, $cmd, $expect) = @_;
    $self->SUPER::cmdexe($cmd,$expect);
}

=head2 cmdSendCheck()

   Run a command and check its exit code by "echo $?".

=head3 Usage
   my ($exitcode,$output) = $host->cmdSendCheck("cat ~/myfile");

=head3 Inputs

=over

=item $cmd

 The shell command to execute on remote host

=item $expect

 Optional, ref to list of hash that describes the interactive expect body for this command.

=back

=head3 Returns

  $exitcode,$output
  if $cmd execution failed, both are undef

=cut

sub cmdSendCheck {
    my ($self, $cmd, $expect) = @_;
    my ($msg,$exitCode) = (undef, undef);
    $check = 'echo $?';
    $msg = $self->cmdexe($cmd,$expect);
    chomp ( $exitCode = $self->cmdexe($check) ) if (defined $msg);
    #chomp $exitCode;
    return ($exitCode,$msg);
}

  
=head2 existsDir($dir)

Check if $dir exists
input: $dir - name of the directory to be checked
output: 1|0 for exists or non-exists

=cut

sub existsDir {
    my ($self, $dir) = @_;
    my $output = $self->cmdexe("ls -ld $dir | cat ");
    return ($output =~ /^d/) ? 1 : 0;
}

=head2 os()

OS of the host
return: Linux|FreeBSD

=cut
sub os {
    my ($conn) = shift;
    chomp(my $os = $conn->cmdexe("uname -s"));
    return $os;
}

=head2 bye()

  Close the connection decently

=cut

sub bye {
     my ($conn) = shift;
     $conn->movState(0) or return undef;
}
  
1;

