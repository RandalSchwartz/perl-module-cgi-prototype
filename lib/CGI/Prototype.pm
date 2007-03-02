package CGI::Prototype;

our @VERSION = 0.75;

use base qw(Class::Prototyped);
use CGI;

__PACKAGE__->reflect->addSlots
  (
   ## main loop stuff
   activate => sub {
     my $self = shift;
     eval {
       my $page = $self->current_page;
       if ($page) {		# it's a response
	 if ($page->validate and $page->store) {
	   $page = $page->next_page;
	   $page->fetch;
	 }
       } else {			# it's an initial call
	 $page = $self->default_page;
	 $page->fetch;
       }
       $page->render;		# show the selected page
     };
     $self->error($@) if $@;	# failed something, go to safe mode
   },
   error => sub {
     my $self = shift;
     my $error = shift;
     $self->display("Content-type: text/plain\n\nERROR: $error");
   },
   [qw(fetch constant)] => 1,	# do nothing by default
   [qw(store constant)] => 1,	# return 1 to say it stored OK
   [qw(validate constant)] => 1, # return 1 to say it validated
   next_page => sub { return shift; }, # stay here
   render => sub {
     my $self = shift;
     my $tt = $self->cached_tt;
     $self->param($self->hidden_page_field_name, $self->name);
     my %vars = (CGI => $self->CGI,
		 PAGE => $self->CGI->hidden($self->hidden_page_field_name),
		 global => $self->vars);
     $tt->process($self->template, \%vars, \my $output)
       or die "running the page: ", $tt->error;
     $self->display($output);
   },
   display => sub {
     my $self = shift;
     my $output = shift;
     print $output;
   },
   ## CGI stuff
   CGI => CGI->new,
   param => sub { shift->CGI->param(@_) }, # convenience method
   delete_param => sub { shift->CGI->delete(@_) }, # delete param items
   ## template stuff
   tt => sub {
     my $self = shift;
     require Template;

     Template->new($self->engine)
       or die "creating tt: $Template::ERROR";
   },
   [qw(cached_tt FIELD autoload)] => sub { shift->tt },
   engine => {},		# if you redefine this, copy cached_tt
   vars => {},
   template => \ '[% CGI.header %]This page intentionally left blank.',
   ## page stuff
   pages => {},
   add_page => sub {
     my $self = shift;
     my $name = shift;
     my $page = $self->new(name => $name, 'class*' => $self, @_);
     $self->pages->{$name} = $page;
   },
   lookup_page_or_die => sub {
     my $self = shift;
     my $page = shift;
     $self->pages->{$page} or die "$self cannot find a page named $page";
   },
   current_page => sub {	# undef if no current page
     my $self = shift;
     my $page_param = $self->param($self->hidden_page_field_name);
     defined $page_param ? $self->pages->{$page_param} : undef;
   },
   default_page => sub {
     my $self = shift;
     my $name = $self->initial_page_name;
     $self->lookup_page_or_die($name);
   },
   initial_page_name => 'initial',
   hidden_page_field_name => '_page',
  );
__PACKAGE__->add_page(initial => ());	# the null application

1;

__END__

=head1 NAME

CGI::Prototype - Create a CGI application by subclassing

=head1 SYNOPSIS

  use CGI::Prototype;
  my $cp = CGI::Prototype->newPackage(MyApp =>
			     [Class::Prototyped-style slots]...);
  $cp->add_page(pagename => [Class::Prototyped-style slots]...);
  ...
  $cp->activate;

=head1 DESCRIPTION

L<CGI::Prototype> creates a C<Class::Prototyped> engine for driving
Template-Toolkit-processed multi-page web apps.

You can create the null application by simply I<activating> it:

  use CGI::Prototype;
  CGI::Prototype->activate;

But this won't be very interesting.  You'll want to "subclass" this
class in a C<Class::Prototyped>-style manner to override most of its
behavior.  Slots can be added to add or alter behavior.  You can
subclass your subclasses when groups of your CGI pages share similar
behavior.  The possibilities are mind-boggling.

The easiest documentation is the source code itself.  It's amazingly
short.  Here are some things that aren't necessarily obvious from the
source, however.

=head2 PAGES

Every page to be rendered to the user has a unique name.  It's easiest
if this name is also a barewordable string.  The default initial page
(and only page, unless you include a C<next_page> override) is called
C<initial>.

Every page is rendered using C<Template>, defined as the page's
C<template> slot.  By default, two items are passed in as variables:
C<PAGE> and C<CGI>.  C<CGI> is a CGI.pm object suitable for accessing
C<param>s and generating HTML.

C<PAGE> is a hidden field that should be placed in any form to be
submitted, and is the only way to get your application to recognize
what response page has been generated to a form.  So, just include it
in your template somewhere, like:

  <form action="POST">
  [% PAGE %]
  ... rest of your form
  </form>

Pages are defined using the C<add_page> method.  For example, to override
the default C<initial> page, you could simply define a new one:

  $cp->add_page(initial =>
    template => \ '[% CGI.header %] Hello world!',
  );

Note that the template can be defined in all the traditional
Template-Toolkit manners: a reference to a scalar, a filehandle, or a
filename searched along Template's include path.

To get from one page to the next, you must have a form and override
the C<next_page> method:

  $cp->add_page(initial =>
	 template => \ '[% CGI.header %] Hello again!
	   <form>[% PAGE %][% CGI.submit(Next) %]</form>',
	  next_page => sub { shift->lookup_page_or_die('final') },
  );

  $cp->add_page(final =>
    template => \ '[% CGI.header %] Goodbye!',
  );

The C<next_page> slot must return a page or C<undef>.  Page objects
are found by calling C<lookup_page_or_die> on yourself.  Page objects
are also the return value from calling C<add_page>, so you can save
them and do something more interesting for a mapping.

=head2 TEMPLATE TOOLKIT INTERFACE

By default, C<Template>'s engine is created with no parameters.  You
may override C<engine>'s slot with a hashref of other parameters.  For
example, to set up a search path, pre-process a common template, and
enable post-chomp, create your app like so:

  CGI::Prototype->newPackage
  (MyApp =>
   engine =>
   {
    INCLUDE_PATH => "/my/app/templates/include",
    PRE_PROCESS => [ 'definitions' ],
    POST_CHOMP => 1,
   },
   );

Note that C<engine> is also overridable on a per-page basis, but the
first engine created will be used for all subsequent hits in a
persistent environment.  To cache more than one engine, be sure to
include this slot definition in every page that also defines
C<engine>:

  [qw(cached_tt FIELD autoload)] => sub { shift->tt },

To pass in variables, create a C<vars> slot returning a hashref of the
variables to be passed in.  By design, these populate the C<global>
hash, so to create C<global.now> with the time of day, use something
like:

    vars => {now => scalar localtime},

If some pages need to add additional variables, the simplest strategy
is to provide the hook in the base class as an additional slot:

    vars => sub {
      my $self = shift;
      return {
	now => scalar localtime,
	%{$self->additional_vars},
      };
    },
    additional_vars => {},

and then override the C<additional_vars> slot in the pages that need
more.

A more general approach is to call the superclass slot in a
subclass page:

    'vars!' => sub {
      my $self = shift;
      return {
        %{$self->reflect->super('vars')}, # get base class vars
        my_var => 52,
      };
    },

This is C<Class::Prototyped>'s method for superclass calling, so see
there for details.

In some cases, you may generate values on the fly or get them
from a database or other source. To populate variables on the
fly during the run and send them to the template, you can do
something like this:

    'vars!' => sub {
      my $self = shift;
      return {
        %{$self->reflect->super('vars')}, # get base class vars
        array_items => $self->array_items,
      };
    },
    fetch => sub {
      my $self = shift;
      my @array_items = qw( Starbuck Apollo );
      $self->reflect->addSlots(
          [qw( array_items FIELD)] => \@array_items,
        );
     },

As above, this uses C<Class::Prototyped>'s method for declaring
variables with reflect.  Beware though that this self-modifies the
objects, and may not work cleanly in a persistent environment.

=head2 ERROR HANDLING

Any uncaught C<die> calls (including failures in C<Template> code) are
vectored to the active C<error> slot, which receives the C<$@> value
as its parameter.  The default C<error> slot renders the message as a
C<text/plain> output (similar to C<use CGI::Carp
qw(fatalsToBrowser)>).  You'll probably want to override this in real
applications.

Note that C<Template> can catch selected view and model errors with
its C<CATCH> mechanism; these will not be considered errors by the
controller code, because they lead to a successful page rendering.
Only uncaught view and model errors (and controller errors before or
after the page has been rendered) will trigger the C<error> slot.

=head2 PERSISTENCE AND PAGE SEQUENCING

Every page can have a C<validate>, C<store>, and C<fetch> slot.  These
should access their C<param> slot to get and put CGI params (using
C<CGI.pm>'s C<param> function).

If C<validate> returns a true value, C<store> is called.  If C<store>
returns true, then the page is considered successful, and C<next_page>
is consulted to move on to the next page.  C<load> is called on the
new page to pre-load form elements (via the I<sticky forms> feature of
C<CGI.pm> by loading the C<param> values), or on the initial page.
C<load> is B<not> called if the page has errors, so that the
sticky-forms feature redisplays the erroneous values.

By default, a stub C<validate> and C<store> routine are provided that
both return true, and C<load> does nothing.

=head1 EXAMPLES

Oh, don't you wish!

=head1 SEE ALSO

L<Class::Prototyped>, L<Template::Manual>

=head1 VERSION

This is CGI::Prototype version 0.75.

=head1 AUTHOR

Randal L. Schwartz: C<merlyn@stonehenge.com>,
Jim Brandt: <cbrandt@buffalo.edu>

=head1 BUGS

None yet.

=cut
