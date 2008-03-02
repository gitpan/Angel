#!/usr/bin/perl -w
use Expect::Angel;
use lib(".");
use Linux;
my $m = "localhost";

my $fn = 'mylog';
our $dut = new Linux(debug => 0, user => 'angel', passwd => 'qatest', dut => $m, goto => 0 , log => $fn) or die "Failed to access $s1 mode\n";

for $s1 ( 1 ... 5 ) {
   $dut->movState($s1) or die "\nfailed to back from $s2 to state $s1\n\n";
   for $s2 (1,2,3,4,5) {
      if ($dut->movState($s2)) {
         print "success from $s1 to $s2\n";
         for ($dut->echo("pwd")) {
            print "$_";
         }
      }else{
         print "failed from $s1 to $s2\n";
         print "current state: $dut->{current}\n";
      }
   }
}
