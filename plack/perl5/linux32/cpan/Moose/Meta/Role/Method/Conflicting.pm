
package Moose::Meta::Role::Method::Conflicting;

use strict;
use warnings;

use base qw(Moose::Meta::Role::Method::Required);

our $VERSION   = '0.82';
$VERSION = eval $VERSION;
our $AUTHORITY = 'cpan:STEVAN';

__PACKAGE__->meta->add_attribute('roles' => (
    reader   => 'roles',
    required => 1,
));

1;

__END__

=pod

=head1 NAME

Moose::Meta::Role::Method::Conflicting - A Moose metaclass for conflicting methods in Roles

=head1 DESCRIPTION

=head1 INHERITANCE

C<Moose::Meta::Role::Method::Conflicting> is a subclass of
L<Moose::Meta::Role::Method::Required>.

=head1 METHODS

=over 4

=item B<< Moose::Meta::Role::Method::Conflicting->new(%options) >>

This creates a new type constraint based on the provided C<%options>:

=over 8

=item * name

The method name. This is required.

=item * roles

The list of role names that generated the conflict. This is required.

=back

=item B<< $method->name >>

Returns the conflicting method's name, as provided to the constructor.

=item B<< $method->roles >>

Returns the roles that generated this conflicting method, as provided to the
constructor.

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006-2009 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
