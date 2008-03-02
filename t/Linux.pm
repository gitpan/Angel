package Linux;
#
# This is example shows complex DUT scenarios by means of Linux machine
# 
# there are 5 states
# 0 - initial state
# 1 - prompt: [~/root]$
# 2 - prompt: [~/root/s1]$
# 3 - prompt: [~/root/s1/s2]$
# 4 - prompt: [~/root/s1/s2/s21]$
# 5 - prompt: [~/root/s1/s2/s22]$
#
# 0 --> 1 --> 2 --> 3 --> 4
#                   |---> 5

# state transition
# by "cd" command
# 
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
   my $states = [( { prompt => '\[~/root\]\$ $' },
                   { prompt => '\[~/root/s1\]\$ $' },
                   { prompt => '\[~/root/s1/s2\]\$ $' },
                   { prompt => '\[~/root/s1/s2/s21\]\$ $' },
                   { prompt => '\[~/root/s1/s2/s22\]\$ $' },
                )];
   $conn->addState(%$_) for (@$states);

   #
   # define transition
   #
   my $trans = {command => "telnet $para->{dut}",
                expect => { 'login: \r?$' => $para->{user},
                            'Password: \r?$' => $para->{passwd} }
               };
   $conn->transitState(0,1,$trans);
   $trans = {command => "cd s1", expect => { } };
   $conn->transitState(1,2,$trans);
   $trans = {command => "cd s2", expect => { } };
   $conn->transitState(2,3,$trans);
   $trans = {command => "cd s21", expect => { } };
   $conn->transitState(3,4,$trans);
   $trans = {command => "cd s22", expect => { } };
   $conn->transitState(3,5,$trans);
   $trans = {command => "cd ..", expect => { } };
   $conn->transitState(5,3,$trans);
   $conn->transitState(4,3,$trans);
   $conn->transitState(3,2,$trans);
   $conn->transitState(2,1,$trans);
   $trans = {nexthop => 3 };
   $conn->transitState(5,4,$trans);
   $conn->transitState(4,5,$trans);
   $trans = {command => "exit", expect => { } };
   $conn->transitState(1,0,$trans);
   if (exists $para->{'goto'}) {
      return $conn->movState($para->{'goto'}) ? $conn : undef;
   }
   $conn;
}


1;

