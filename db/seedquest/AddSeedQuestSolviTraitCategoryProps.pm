#!/usr/bin/env perl

=head1 NAME

AddSeedQuestSolviTraitCategoryProps

=head1 SYNOPSIS

mx-run AddSeedQuestSolviTraitCategoryProps [options] -H hostname -D dbname -u username [-F]

=head1 DESCRIPTION

Adds trait_categories=0 to existing SeedQuest Solvi numeric variables so Breedbase phenotype verification has complete trait properties.

=cut

package AddSeedQuestSolviTraitCategoryProps;

use Moose;
use Try::Tiny;

extends 'CXGN::Metadata::Dbpatch';

has '+description' => ( default => <<'' );
Adds empty trait_categories to SeedQuest Solvi numeric variables

has '+prereq' => (
    default => sub {
        [],
    },
);

my @ACCESSIONS = map { sprintf('SOLVI_%06d', $_) } 1 .. 18;

sub patch {
    my $self = shift;

    print STDOUT "Executing the patch:\n " . $self->name . ".\n\nDescription:\n  " . $self->description . ".\n\nExecuted by:\n " . $self->username . " .";
    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";
    print STDOUT "\nExecuting the SQL commands.\n";

    my $dbh = $self->dbh;

    try {
        $dbh->begin_work;

        my $db_id = _db_id($dbh, 'SQ');
        my $trait_categories_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_categories');

        for my $accession (@ACCESSIONS) {
            my $cvterm_id = _cvterm_id_by_dbxref($dbh, $db_id, $accession);
            _replace_cvtermprop($dbh, $cvterm_id, $trait_categories_type_id, '');
        }

        $dbh->commit;
    } catch {
        my $error = $_;
        eval { $dbh->rollback };
        die "Load failed! $error\n";
    };

    print "You're done!\n";
}

sub _db_id {
    my ($dbh, $name) = @_;
    my ($db_id) = $dbh->selectrow_array('select db_id from db where name = ?', undef, $name);
    die "Required db $name was not found" unless $db_id;
    return $db_id;
}

sub _cvterm_id_by_dbxref {
    my ($dbh, $db_id, $accession) = @_;
    my ($cvterm_id) = $dbh->selectrow_array(
        q{
            select cvterm.cvterm_id
            from cvterm
            join dbxref on dbxref.dbxref_id = cvterm.dbxref_id
            where dbxref.db_id = ? and dbxref.accession = ?
        },
        undef,
        $db_id,
        $accession,
    );
    die "Required Solvi cvterm SQ:$accession was not found" unless $cvterm_id;
    return $cvterm_id;
}

sub _replace_cvtermprop {
    my ($dbh, $cvterm_id, $type_id, $value) = @_;

    $dbh->do(
        'delete from cvtermprop where cvterm_id = ? and type_id = ?',
        undef,
        $cvterm_id,
        $type_id,
    );

    $dbh->do(
        'insert into cvtermprop (cvterm_id, type_id, value, rank) values (?, ?, ?, 0)',
        undef,
        $cvterm_id,
        $type_id,
        $value,
    );
}

sub _cvterm_id_by_name {
    my ($dbh, $cv_name, $term_name) = @_;
    my ($cvterm_id) = $dbh->selectrow_array(
        q{
            select t.cvterm_id
            from cvterm t
            join cv c on c.cv_id = t.cv_id
            where c.name = ? and t.name = ?
        },
        undef,
        $cv_name,
        $term_name,
    );
    die "Required cvterm $cv_name:$term_name was not found" unless $cvterm_id;
    return $cvterm_id;
}

1;
