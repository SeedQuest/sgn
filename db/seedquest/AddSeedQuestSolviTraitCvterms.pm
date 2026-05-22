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
    {
        accession => 'SOLVI_000001',
        name => 'Canopy NDVI - mean',
        object_accession => 'SOLVI_OBJECT_000001',
        entity => 'Canopy',
        attribute => 'NDVI',
        statistic => 'mean',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000002',
        name => 'Canopy NDVI - median',
        object_accession => 'SOLVI_OBJECT_000001',
        entity => 'Canopy',
        attribute => 'NDVI',
        statistic => 'median',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000003',
        name => 'Canopy NDVI - stdev',
        object_accession => 'SOLVI_OBJECT_000001',
        entity => 'Canopy',
        attribute => 'NDVI',
        statistic => 'stdev',
        decimal_places => '4',
        minimum => '0',
        maximum => '2',
    },
    {
        accession => 'SOLVI_000004',
        name => 'Canopy NDRE - mean',
        object_accession => 'SOLVI_OBJECT_000002',
        entity => 'Canopy',
        attribute => 'NDRE',
        statistic => 'mean',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000005',
        name => 'Canopy NDRE - median',
        object_accession => 'SOLVI_OBJECT_000002',
        entity => 'Canopy',
        attribute => 'NDRE',
        statistic => 'median',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000006',
        name => 'Canopy NDRE - stdev',
        object_accession => 'SOLVI_OBJECT_000002',
        entity => 'Canopy',
        attribute => 'NDRE',
        statistic => 'stdev',
        decimal_places => '4',
        minimum => '0',
        maximum => '2',
    },
    {
        accession => 'SOLVI_000007',
        name => 'Canopy OSAVI - mean',
        object_accession => 'SOLVI_OBJECT_000003',
        entity => 'Canopy',
        attribute => 'OSAVI',
        statistic => 'mean',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000008',
        name => 'Canopy OSAVI - median',
        object_accession => 'SOLVI_OBJECT_000003',
        entity => 'Canopy',
        attribute => 'OSAVI',
        statistic => 'median',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000009',
        name => 'Canopy OSAVI - stdev',
        object_accession => 'SOLVI_OBJECT_000003',
        entity => 'Canopy',
        attribute => 'OSAVI',
        statistic => 'stdev',
        decimal_places => '4',
        minimum => '0',
        maximum => '2',
    },
    {
        accession => 'SOLVI_000010',
        name => 'Canopy GRVI - mean',
        object_accession => 'SOLVI_OBJECT_000004',
        entity => 'Canopy',
        attribute => 'GRVI',
        statistic => 'mean',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000011',
        name => 'Canopy GRVI - median',
        object_accession => 'SOLVI_OBJECT_000004',
        entity => 'Canopy',
        attribute => 'GRVI',
        statistic => 'median',
        decimal_places => '4',
        minimum => '-1',
        maximum => '1',
    },
    {
        accession => 'SOLVI_000012',
        name => 'Canopy GRVI - stdev',
        object_accession => 'SOLVI_OBJECT_000004',
        entity => 'Canopy',
        attribute => 'GRVI',
        statistic => 'stdev',
        decimal_places => '4',
        minimum => '0',
        maximum => '2',
    },
    {
        accession => 'SOLVI_000013',
        name => 'Canopy NIR reflectance - mean',
        object_accession => 'SOLVI_OBJECT_000005',
        entity => 'Canopy',
        attribute => 'NIR reflectance',
        statistic => 'mean',
        decimal_places => '4',
        minimum => '0',
    },
    {
        accession => 'SOLVI_000014',
        name => 'Canopy NIR reflectance - median',
        object_accession => 'SOLVI_OBJECT_000005',
        entity => 'Canopy',
        attribute => 'NIR reflectance',
        statistic => 'median',
        decimal_places => '4',
        minimum => '0',
    },
    {
        accession => 'SOLVI_000015',
        name => 'Canopy NIR reflectance - stdev',
        object_accession => 'SOLVI_OBJECT_000005',
        entity => 'Canopy',
        attribute => 'NIR reflectance',
        statistic => 'stdev',
        decimal_places => '4',
        minimum => '0',
    },
    {
        accession => 'SOLVI_000016',
        name => 'Canopy height (cm) - mean',
        object_accession => 'SOLVI_OBJECT_000006',
        entity => 'Canopy',
        attribute => 'height',
        statistic => 'mean',
        decimal_places => '2',
        minimum => '0',
    },
    {
        accession => 'SOLVI_000017',
        name => 'Canopy height (cm) - median',
        object_accession => 'SOLVI_OBJECT_000006',
        entity => 'Canopy',
        attribute => 'height',
        statistic => 'median',
        decimal_places => '2',
        minimum => '0',
    },
    {
        accession => 'SOLVI_000018',
        name => 'Canopy height (cm) - stdev',
        object_accession => 'SOLVI_OBJECT_000006',
        entity => 'Canopy',
        attribute => 'height',
        statistic => 'stdev',
        decimal_places => '2',
        minimum => '0',
    },
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
        my $trait_categories_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_categories');
        my $trait_decimal_places_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_decimal_places');
        my $trait_minimum_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_minimum');
        my $trait_maximum_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_maximum');
        my $trait_repeat_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_repeat_type');
        my $trait_entity_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_entity');
        my $trait_attribute_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_attribute');
        my $trait_method_name_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_method_name');
        my $trait_method_description_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_method_description');
        my $trait_method_class_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_method_class');
        my $trait_method_formula_type_id = _cvterm_id_by_name($dbh, 'trait_property', 'trait_method_formula');

        my %object_ids;
        for my $object (@OBJECTS) {
            my ($accession, $name) = @$object;
            $object_ids{$accession} = _ensure_cvterm($dbh, $db_id, $cv_id, $accession, $name);
        }

        for my $variable (@VARIABLES) {
            my $variable_id = _ensure_cvterm($dbh, $db_id, $cv_id, $variable->{accession}, $variable->{name});
            _ensure_relationship($dbh, $variable_id, $variable_of_type_id, $object_ids{$variable->{object_accession}});
            _replace_cvtermprop($dbh, $variable_id, $trait_format_type_id, 'numeric');
            _replace_cvtermprop($dbh, $variable_id, $trait_categories_type_id, '');
            _replace_cvtermprop($dbh, $variable_id, $trait_repeat_type_id, 'time_series');
            _replace_cvtermprop($dbh, $variable_id, $trait_decimal_places_type_id, $variable->{decimal_places});
            _replace_cvtermprop($dbh, $variable_id, $trait_minimum_type_id, $variable->{minimum});
            _replace_cvtermprop($dbh, $variable_id, $trait_maximum_type_id, $variable->{maximum});
            _replace_cvtermprop($dbh, $variable_id, $trait_entity_type_id, $variable->{entity});
            _replace_cvtermprop($dbh, $variable_id, $trait_attribute_type_id, $variable->{attribute});
            _replace_cvtermprop($dbh, $variable_id, $trait_method_name_type_id, "Solvi $variable->{statistic} zonal statistic");
            _replace_cvtermprop($dbh, $variable_id, $trait_method_description_type_id, _method_description($variable));
            _replace_cvtermprop($dbh, $variable_id, $trait_method_class_type_id, 'computational');
            _replace_cvtermprop($dbh, $variable_id, $trait_method_formula_type_id, _method_formula($variable));
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

sub _replace_cvtermprop {
    my ($dbh, $cvterm_id, $type_id, $value) = @_;
    return unless defined $value;

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

sub _method_description {
    my ($variable) = @_;
    return "Computed from a Solvi zonal statistics CSV for each Breedbase plot zone; statistic=$variable->{statistic}, attribute=$variable->{attribute}.";
}

sub _method_formula {
    my ($variable) = @_;
    return 'Solvi exported Height (m) values are converted to centimeters before import.'
        if $variable->{attribute} eq 'height';
    return "Solvi exported $variable->{attribute} $variable->{statistic} value.";
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
