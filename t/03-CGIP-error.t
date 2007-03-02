#! perl
use Test::More no_plan;

require_ok 'CGI::Prototype';

{
  package My::App;
  @ISA = qw(CGI::Prototype);

  sub template {
    \ '[% THROW "up" "payload" %]';
  }
}

{
  open my $stdout, ">&STDOUT" or die;
  open STDOUT, '>test.out' or die;
  END { unlink 'test.out' }
  My::App->activate;
  open STDOUT, ">&=".fileno($stdout) or die;
}

open IN, "<test.out";
like join("", <IN>),
  qr/up error - payload/,
  'proper error is thrown';




