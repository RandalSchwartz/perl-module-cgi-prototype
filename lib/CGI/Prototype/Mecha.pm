use strict;

package CGI::Prototype::Mecha;
use base qw(WWW::Mechanize);
BEGIN { require Test::More; *diag = \&Test::More::diag }

require CGI;

my $OUTPUT;			# has to be visible to "new" and "simple_request"

sub new {			# extend SUPER::new
  my $class = shift;
  my %options = @_;

  my $protoapp = delete $options{protoapp}
    or die "missing protoapp class name";
  my $self = $class->SUPER::new(%options);
  eval "require $protoapp";	# bring in the code
  die $@ if $@;			# throw up if needed
  $self->{protoapp} = $protoapp->reflect; # mirror
  $self->{protoapp}->addSlots
    (display => sub {
       my $self = shift;
       my $output = shift;
       $OUTPUT .= $output;
     },
    );
  return $self;
}

sub simple_request {
  my $self = shift;
  my $request = shift;
  if (@_ and defined($_[0])) {			# oops can't handle this...
    require Data::Dumper;
    die "extra parameters:", Data::Dumper::Dumper(\@_);
  }

  my $mirror = $self->{protoapp};
  my $uri = URI->new($request->uri);
  unless ($uri->scheme eq "http" and $uri->host eq "mecha") {
    ## eventually, return $self->SUPER::simple_request($request)
    ## warn "returning 404 for $uri";
    return HTTP::Response->new(404, 'not found', [], "$uri");
  }

  my $params;
  if ($request->method eq 'POST') {
    if (my @parts = $request->parts) {
      require Data::Dumper;
      my %p;
      ## warn "parts are ", Data::Dumper::Dumper(\@parts);
      for my $part (@parts) {
	my $value = $part->content;
	my $key = $part->header('content-disposition');
	$key =~ s/^form-data; name="(.*)"/$1/s or die "bad form-data: $key";
	$key =~ s/\\"/"/g;
	push @{$p{$key}}, $value;
      }
      ## warn "processed parts are ", Data::Dumper::Dumper(\%p);
      $params = \%p;
    } else {
      $params = $request->content;
    }
  } else {
    $params = $uri->query;
  }
  ## print STDERR map "# params: $_\n", split /\n/, $params;
  local $ENV{SERVER_NAME} = "mecha";

  ## need to fake up the CGI object now:
  $mirror->addSlot
    (initialize_CGI => sub {
       my $self = shift;
       $self->reflect->addSlot(CGI => scalar CGI->new($params));
     });

  $OUTPUT = "";

  eval { $mirror->object->activate };
  if ($@) {
    ## warn "returning 500 for $@";
    return HTTP::Response->new(500, 'internal error', [], "$@");
  }
  my $msg = HTTP::Message->parse($OUTPUT);
  my ($status, $message) = $msg->header('status') ?
    split ' ', $msg->header('status'), 2 : (200, 'ok');
  ## warn "## status is $status message is $message";
  my $response = HTTP::Response->new($status, $message,
				     $msg->headers, $msg->content);
  $response->request($request);
  ## warn "returning response:\n", $response->as_string;
  $response;
}

sub diag_response {
  diag(join '', shift->res->as_string);
}

sub diag_links {
  for (shift->links) {
    diag(join "", $_->text, " to ", $_->url);
  }
}

sub diag_forms {
  for (shift->forms) {
    diag(join "", $_->dump);
  }
}

1;

__END__

=head1 NAME

CGI::Prototype::Mecha - test CGI::Prototype applications with WWW::Mechanize

=head1 SYNOPSIS

  use CGI::Prototype::Mecha;
  my $m = CGI::Prototype::Mecha->new(protoapp => 'My::App');

  $m->get('http://mecha/');
  ok $m->success, "fetched welcome page" or $m->diag_response;
  like $m->content, qr/Select a task/, "welcome page content verified";

=head1 DESCRIPTION

C<WWW::Mechanize> combined with C<Test::More> is a great toolbench for
testing a web application.  But you need to have your code installed
in the right location on a running server, and you can't poke behind
the scenes to see if data structures or databases in your application
are as they are expected to be after a particular web hit.

Enter C<CGI::Prototype::Mecha>, a subclass of C<WWW::Mechanize>.

Simply create a Mecha object, giving it the name of your
C<CGI::Prototype>-derived application class, and "visit" the magic URL
of C<http://mecha/>.  Your application is fired up (loading the
classes as needed), and you get a "response" as if it were being sent
to the browser.

But, your object is in the same program as your test, so you can set
environment variables to simulate auth success or control testing
databases.  Or even capture C<STDERR> into a file to make sure that a
particular error log value is or is not being written.

=head2 Methods

=over 4

=item new

Extended from C<WWW::Mechanize>.  An additional C<protoapp> parameter
is understood, expecting a C<CGI::Prototype>-derived application class
(which should be located in the current C<@INC>).  Returns the mecha
object.

=item simple_request

Extended from C<WWW::Mechanize> (which inherits it directly from
C<LWP::UserAgent>.  This is where the magic happens.

Note that visiting any URL that does not start with C<http://mecha/>
is fatal.  A future version may fall back to the original
C<WWW::Mechanize>, letting you test your app's outbound links
properly.

=item diag_response

A convenience method that dumps the result "as_string" via C<diag()>
from C<Test::More>.

=item diag_links

A convenience method that dumps all the links (text/url) via C<diag()>.

=item diag_forms

A convenience method that dumps all the forms via C<diag()>.

=back

=head1 SEE ALSO

L<CGI::Prototype>, L<WWW::Mechanize>, L<Test::More>

=head1 AUTHOR

Randal L. Schwartz, E<lt>merlyn@stonehenge.comE<gt>

Special thanks to Geekcruises.com and an unnamed large university
for providing funding for the development of this module.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003, 2004 by Randal L. Schwartz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.
