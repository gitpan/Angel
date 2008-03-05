use 5.008005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Expect::Angel',
    VERSION_FROM      => 'lib/Expect/Angel.pm', # finds $VERSION
    PREREQ_PM         => {Expect => 1.20}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Expect/Angel.pm', # retrieve abstract from module
       AUTHOR         => 'Ming Zhang <ming2004@gmail.com>') : ()),
);
