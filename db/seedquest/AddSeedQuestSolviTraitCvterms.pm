#!/usr/bin/env perl

=head1 NAME

AddSeedQuestSolviTraitCvterms

=head1 SYNOPSIS

mx-run AddSeedQuestSolviTraitCvterms [options] -H hostname -D dbname -u username [-F]

=head1 DESCRIPTION

Adds SeedQuest Solvi CSV ontology variables used by the Solvi CSV preview/import workflow.

=cut

package AddSeedQuestSolviTraitCvterms;

use Moose;
use Try::Tiny;

extends 'CXGN::Metadata::Dbpatch';

has '+description' => ( default => <<'' );
Adds SeedQuest Solvi CSV ontology variables

has '+prereq' => (
    default => sub {
        [],
    },
);

my @OBJECTS = (
    [ 'SOLVI_OBJECT_000001', 'Canopy NDVI' ],
    [ 'SOLVI_OBJECT_000002', 'Canopy NDRE' ],
    [ 'SOLVI_OBJECT_000003', 'Canopy OSAVI' ],
    [ 'SOLVI_OBJECT_000004', 'Canopy GRVI' ],
    [ 'SOLVI_OBJECT_000005', 'Canopy NIR reflectance' ],
    [ 'SOLVI_OBJECT_000006', 'Canopy height' ],
);

my @VARIABLES = (
    [ 'SOLVI_000001', 'Canopy NDVI - mean',              'SOLVI_OBJECT_000001' ],
    [ 'SOLVI_000002', 'Canopy NDVI - median',            'SOLVI_OBJECT_000001' ],
    [ 'SOLVI_000003', 'Canopy NDVI - stdev',             'SOLVI_OBJECT_000001' ],
    [ 'SOLVI_000004', 'Canopy NDRE - mean',              'SOLVI_OBJECT_000002' ],
    [ 'SOLVI_000005', 'Canopy NDRE - median',            'SOLVI_OBJECT_000002' ],
    [ 'SOLVI_000006', 'Canopy NDRE - stdev',             'SOLVI_OBJECT_000002' ],
    [ 'SOLVI_000007', 'Canopy OSAVI - mean',             'SOLVI_OBJECT_000003' ],
    [ 'SOLVI_000008', 'Canopy OSAVI - median',           'SOLVI_OBJECT_000003' ],
    [ 'SOLVI_000009', 'Canopy OSAVI - stdev',            'SOLVI_OBJECT_000003' ],
    [ 'SOLVI_000010', 'Canopy GRVI - mean',              'SOLVI_OBJECT_000004' ],
    [ 'SOLVI_000011', 'Canopy GRVI - median',            'SOLVI_OBJECT_000004' ],
    [ 'SOLVI_000012', 'Canopy GRVI - stdev',             'SOLVI_OBJECT_000004' ],
    [ 'SOLVI_000013', 'Canopy NIR reflectance - mean',   'SOLVI_OBJECT_000005' ],
    [ 'SOLVI_000014', 'Canopy NIR reflectance - median', 'SOLVI_OBJECT_000005' ],
    [ 'SOLVI_000015', 'Canopy NIR reflectance - stdev',  'SOLVI_OBJECT_000005' ],
    [ 'SOLVI_000016', 'Canopy height (cm) - mean',       'SOLVI_OBJECT_000006' ],
    [ 'SOLVI_000017', 'Canopy height (cm) - median',     'SOLVI_OBJECT_000006' ],
    [ 'SOLVI_000018', 'Canopy height (cm) - stdev',      'SOLVI_OBJECT_000006' ],
);

sub patch {
    my $self = shift;

    print STDOUT "Executing the patch:\n " . $self->name . ".\n\nDescription:\n  " . $self->description . ".\n\nExecuted by:\n " . $self->username . " .";
    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";
    print STDOUT "\nExecuting the SQL commands.\n";

    my $dbh = $self->dbh;

    try {
        $dbh->begin_work;

        my $db_id = _ensure_db($dbh);
        my $cv_id = _ensure_cv($dbh);
        my $variable_of_type_id = _cvterm_id_by_name($dbh, 'relationship', 'VARIABLE_OF');
        my $trait_format_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_format');
        my $trait_repeat_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_repeat_type');

        my %object_ids;
        for my $object (@OBJECTS) {
            my ($accession, $name) = @$object;
            $object_ids{$accession} = _ensure_cvterm($dbh, $db_id, $cv_id, $accession, $name);
        }

        for my $variable (@VARIABLES) {
            my ($accession, $name, $object_accession) = @$variable;
            my $variable_id = _ensure_cvterm($dbh, $db_id, $cv_id, $accession, $name);
            _ensure_relationship($dbh, $variable_id, $variable_of_type_id, $object_ids{$object_accession});
            _ensure_cvtermprop($dbh, $variable_id, $trait_format_type_id, 'numeric');
            _ensure_cvtermprop($dbh, $variable_id, $trait_repeat_type_id, 'time_series');
        }

        $dbh->commit;
    } catch {
        my $error = $_;
        eval { $dbh->rollback };
        die "Load failed! $error\n";
    };

    print "You're done!\n";
}

sub _ensure_db {
    my ($dbh) = @_;
    my ($db_id) = $dbh->selectrow_array('select db_id from db where name = ?', undef, 'SQ');
    return $db_id if $db_id;

    ($db_id) = $dbh->selectrow_array(
        q{
            insert into db (name, description, urlprefix)
            values (?, ?, ?)
            returning db_id
        },
        undef,
        'SQ',
        'SeedQuest local ontology terms',
        'https://seedquest.com.ua/ontology/SQ:',
    );
    return $db_id;
}

sub _ensure_cv {
    my ($dbh) = @_;
    my ($cv_id) = $dbh->selectrow_array('select cv_id from cv where name = ?', undef, 'SeedQuest_ontology');
    return $cv_id if $cv_id;

    ($cv_id) = $dbh->selectrow_array(
        q{
            insert into cv (name, definition)
            values (?, ?)
            returning cv_id
        },
        undef,
        'SeedQuest_ontology',
        'SeedQuest local ontology terms',
    );
    return $cv_id;
}

sub _ensure_cvterm {
    my ($dbh, $db_id, $cv_id, $accession, $name) = @_;

    my $dbxref_id = _ensure_dbxref($dbh, $db_id, $accession, $name);
    my ($cvterm_id) = $dbh->selectrow_array(
        'select cvterm_id from cvterm where dbxref_id = ?',
        undef,
        $dbxref_id,
    );
    return $cvterm_id if $cvterm_id;

    ($cvterm_id) = $dbh->selectrow_array(
        q{
            insert into cvterm (cv_id, name, definition, dbxref_id, is_obsolete, is_relationshiptype)
            values (?, ?, ?, ?, 0, 0)
            returning cvterm_id
        },
        undef,
        $cv_id,
        $name,
        $name,
        $dbxref_id,
    );
    return $cvterm_id;
}

sub _ensure_dbxref {
    my ($dbh, $db_id, $accession, $description) = @_;

    my ($dbxref_id) = $dbh->selectrow_array(
        'select dbxref_id from dbxref where db_id = ? and accession = ?',
        undef,
        $db_id,
        $accession,
    );
    return $dbxref_id if $dbxref_id;

    ($dbxref_id) = $dbh->selectrow_array(
        q{
            insert into dbxref (db_id, accession, version, description)
            values (?, ?, '', ?)
            returning dbxref_id
        },
        undef,
        $db_id,
        $accession,
        $description,
    );
    return $dbxref_id;
}

sub _ensure_relationship {
    my ($dbh, $subject_id, $type_id, $object_id) = @_;

    my ($exists) = $dbh->selectrow_array(
        q{
            select cvterm_relationship_id
            from cvterm_relationship
            where subject_id = ? and type_id = ? and object_id = ?
        },
        undef,
        $subject_id,
        $type_id,
        $object_id,
    );
    return if $exists;

    $dbh->do(
        'insert into cvterm_relationship (subject_id, type_id, object_id) values (?, ?, ?)',
        undef,
        $subject_id,
        $type_id,
        $object_id,
    );
}

sub _ensure_cvtermprop {
    my ($dbh, $cvterm_id, $type_id, $value) = @_;

    my ($exists) = $dbh->selectrow_array(
        q{
            select cvtermprop_id
            from cvtermprop
            where cvterm_id = ? and type_id = ? and value = ? and rank = 0
        },
        undef,
        $cvterm_id,
        $type_id,
        $value,
    );
    return if $exists;

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
