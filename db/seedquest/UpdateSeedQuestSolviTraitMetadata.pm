#!/usr/bin/env perl

=head1 NAME

UpdateSeedQuestSolviTraitMetadata

=head1 SYNOPSIS

mx-run UpdateSeedQuestSolviTraitMetadata [options] -H hostname -D dbname -u username [-F]

=head1 DESCRIPTION

Completes SeedQuest Solvi observation variable metadata: numeric scale properties, method properties, entity/attribute, and time-series repeat type.

=cut

package UpdateSeedQuestSolviTraitMetadata;

use Moose;
use Try::Tiny;

extends 'CXGN::Metadata::Dbpatch';

has '+description' => ( default => <<'' );
Completes SeedQuest Solvi observation variable metadata

has '+prereq' => (
    default => sub {
        [],
    },
);

my @VARIABLES = (
    [ 'SOLVI_000001', 'Canopy', 'NDVI',            'mean',   '4', '-1', '1' ],
    [ 'SOLVI_000002', 'Canopy', 'NDVI',            'median', '4', '-1', '1' ],
    [ 'SOLVI_000003', 'Canopy', 'NDVI',            'stdev',  '4', '0',  '2' ],
    [ 'SOLVI_000004', 'Canopy', 'NDRE',            'mean',   '4', '-1', '1' ],
    [ 'SOLVI_000005', 'Canopy', 'NDRE',            'median', '4', '-1', '1' ],
    [ 'SOLVI_000006', 'Canopy', 'NDRE',            'stdev',  '4', '0',  '2' ],
    [ 'SOLVI_000007', 'Canopy', 'OSAVI',           'mean',   '4', '-1', '1' ],
    [ 'SOLVI_000008', 'Canopy', 'OSAVI',           'median', '4', '-1', '1' ],
    [ 'SOLVI_000009', 'Canopy', 'OSAVI',           'stdev',  '4', '0',  '2' ],
    [ 'SOLVI_000010', 'Canopy', 'GRVI',            'mean',   '4', '-1', '1' ],
    [ 'SOLVI_000011', 'Canopy', 'GRVI',            'median', '4', '-1', '1' ],
    [ 'SOLVI_000012', 'Canopy', 'GRVI',            'stdev',  '4', '0',  '2' ],
    [ 'SOLVI_000013', 'Canopy', 'NIR reflectance', 'mean',   '4', '0',  undef ],
    [ 'SOLVI_000014', 'Canopy', 'NIR reflectance', 'median', '4', '0',  undef ],
    [ 'SOLVI_000015', 'Canopy', 'NIR reflectance', 'stdev',  '4', '0',  undef ],
    [ 'SOLVI_000016', 'Canopy', 'height',          'mean',   '2', '0',  undef ],
    [ 'SOLVI_000017', 'Canopy', 'height',          'median', '2', '0',  undef ],
    [ 'SOLVI_000018', 'Canopy', 'height',          'stdev',  '2', '0',  undef ],
);

sub patch {
    my $self = shift;

    print STDOUT "Executing the patch:\n " . $self->name . ".\n\nDescription:\n  " . $self->description . ".\n\nExecuted by:\n " . $self->username . " .";
    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";
    print STDOUT "\nExecuting the SQL commands.\n";

    my $dbh = $self->dbh;

    try {
        $dbh->begin_work;

        my $db_id = _db_id($dbh, 'SQ');
        my %type_ids = map { $_ => _cvterm_id_by_name($dbh, 'trait_property', $_) } qw(
            trait_attribute
            trait_categories
            trait_decimal_places
            trait_entity
            trait_format
            trait_maximum
            trait_method_class
            trait_method_description
            trait_method_formula
            trait_method_name
            trait_minimum
            trait_repeat_type
        );

        for my $variable (@VARIABLES) {
            my ($accession, $entity, $attribute, $statistic, $decimal_places, $minimum, $maximum) = @$variable;
            my $cvterm_id = _cvterm_id_by_dbxref($dbh, $db_id, $accession);

            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_format}, 'numeric');
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_categories}, '');
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_repeat_type}, 'time_series');
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_decimal_places}, $decimal_places);
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_minimum}, $minimum);
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_maximum}, $maximum);
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_entity}, $entity);
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_attribute}, $attribute);
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_method_name}, "Solvi $statistic zonal statistic");
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_method_description}, "Computed from a Solvi zonal statistics CSV for each Breedbase plot zone; statistic=$statistic, attribute=$attribute.");
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_method_class}, 'computational');
            _replace_cvtermprop($dbh, $cvterm_id, $type_ids{trait_method_formula}, _method_formula($attribute, $statistic));

            $dbh->do(
                'update cvterm set definition = ? where cvterm_id = ?',
                undef,
                "SeedQuest Solvi $statistic observation variable for $entity $attribute.",
                $cvterm_id,
            );
        }

        $dbh->commit;
    } catch {
        my $error = $_;
        eval { $dbh->rollback };
        die "Load failed! $error\n";
    };

    print "You're done!\n";
}

sub _method_formula {
    my ($attribute, $statistic) = @_;
    return 'Solvi exported Height (m) values are converted to centimeters before import.'
        if $attribute eq 'height';
    return "Solvi exported $attribute $statistic value.";
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
    return unless defined $value;

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
