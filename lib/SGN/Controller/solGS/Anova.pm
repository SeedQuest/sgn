
=head1 AUTHOR

Isaak Y Tecle <iyt2@cornell.edu>

=head1 Name

SGN::Controller::solGS::Anova - a controller for ANOVA. For now, this implements a one-way
single trial ANOVA with a possibility for simultanously running anova for multiple traits.

=cut

package SGN::Controller::solGS::Anova;

use Moose;
use namespace::autoclean;

use Carp qw/ carp confess croak /;

use CXGN::Trial;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Slurp qw /write_file read_file/;
use File::Spec::Functions;
use File::Path qw /mkpath/;
use JSON;
use List::Util qw/any uniq all/;
use List::MoreUtils qw/firstidx/;
use Scalar::Util qw /weaken reftype looks_like_number/;
use SGN::Model::Cvterm;
use Storable qw/nstore retrieve/;
use URI::FromHash 'uri';

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
);

sub anova_check_design : Path('/anova/check/design/') Args(0) {
    my ( $self, $c ) = @_;

    my $args = $c->req->param('arguments');
    $c->controller('solGS::Utils')->stash_json_args( $c, $args );

    my $design    = $self->get_trial_design($c);
    my $supported = $self->check_design_support($design) if $design;

    if ( !$design ) {
        $c->stash->{rest}{'Error'} = 'This trial has no design to apply ANOVA.';
    }
    elsif ( $design && !$supported ) {
        $c->stash->{rest}{'Error'} = $design
          . ' design is not supported yet. Please report this to the database team. ';
    }
    else {
        $c->stash->{rest}{'Design'} = $design;
    }

}

sub anova_traits_list : Path('/anova/traits/list/') Args(0) {
    my ( $self, $c ) = @_;

    my $args = $c->req->param('arguments');
    $c->controller('solGS::Utils')->stash_json_args( $c, $args );

    my $traits = $self->anova_traits($c);
    $c->stash->{rest}{anova_traits} = $traits;

}

sub anova_phenotype_data : Path('/anova/phenotype/data/') Args(0) {
    my ( $self, $c ) = @_;

    my $args = $c->req->param('arguments');
    $c->controller('solGS::Utils')->stash_json_args( $c, $args );

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->controller('solGS::Trait')->get_trait_details( $c, $trait_id );

    my $pheno_file = $self->trial_phenotype_file($c);

    if ( !-s $pheno_file ) {

        $pheno_file = $self->create_anova_phenodata_file($c);

        if ( !-s $pheno_file ) {
            $c->stash->{rest}{'Error'} =
              'There is no phenotype data for this  trial.';
        }

        if ( @{ $c->error } ) {
            $c->stash->{rest}{'Error'} =
              'There was error querying for the phenotype data.';
        }
    }
    else {
        my $categorical = $self->check_categorical_dependent_variable($c);
        if ($categorical) {
            $c->stash->{rest}{'Error'} =
"The trait data is not all numeric. Some or all of the trait values are text. ";
        }
        else {
            $c->stash->{rest}{'success'} = 'Success.';
        }
    }

    my $traits_abbrs = $self->get_traits_abbrs($c);
    $c->stash->{rest}{trial_id}     = $trial_id;
    $c->stash->{rest}{traits_abbrs} = $traits_abbrs;

}

sub anova_analyis : Path('/anova/analysis/') Args(0) {
    my ( $self, $c ) = @_;

    my $args = $c->req->param('arguments');
    $c->controller('solGS::Utils')->stash_json_args( $c, $args );

    my $anova_result = $self->check_anova_output($c);

    $c->controller('solGS::Trait')
      ->get_trait_details( $c, $c->stash->{trait_id} );

    if ( !$anova_result ) {
        $self->run_anova($c);
    }

    $self->prepare_response($c);

}

sub anova_traits {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};

    my $traits =
      $c->controller('solGS::Search')->model($c)->trial_traits($trial_id);
    my $clean_traits = $c->controller('solGS::Utils')->remove_ontology($traits);

    return $clean_traits;

}

sub create_anova_phenodata_file {
    my ( $self, $c ) = @_;

    my $cached = $c->controller('solGS::CachedResult')
      ->check_cached_phenotype_data( $c, $c->stash->{trial_id} );

    if ( !$cached ) {
        $self->anova_query_jobs_file($c);
        my $queries = $c->stash->{anova_query_jobs_file};

        $c->stash->{dependent_jobs} = $queries;
        $c->controller('solGS::AsyncJob')->run_async($c);
    }

    my $pheno_file = $self->trial_phenotype_file($c);

    return $pheno_file;

}

sub trial_phenotype_file {
    my ( $self, $c ) = @_;

    $c->controller('solGS::Files')
      ->phenotype_file_name( $c, $c->stash->{trial_id} );
    return $c->stash->{phenotype_file_name};

}

sub get_trial_design {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};

    my $trial = CXGN::Trial->new(
        {
            bcs_schema => $self->schema($c),
            trial_id   => $trial_id
        }
    );

    my $design = $trial->get_design_type();

    return $design;

}

sub check_design_support {
    my ( $self, $design ) = @_;

    my $supported_designs = $self->supported_designs();

    my ($match) = grep( /$design/, @$supported_designs );

    return $match;

}

sub supported_designs {
    my $self = shift;

    my $supported_designs = [qw(Alpha, Augmented, RCBD, CRD)];

    return $supported_designs;

}

sub get_traits_abbrs {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->stash->{pop_id} = $trial_id;
    $c->controller('solGS::Trait')->get_all_traits( $c, $trial_id );
    $c->controller('solGS::Files')->all_traits_file( $c, $trial_id );

    $c->controller('solGs::Trait')->get_trait_details( $c, $trait_id );
    my $trait_abbr = $c->stash->{trait_abbr};

    my $id_abbr      = { 'trait_id' => $trait_id, 'trait_abbr' => $trait_abbr };
    my $json         = JSON->new();
    my $traits_abbrs = $json->encode($id_abbr);

    return $traits_abbrs;
}

sub check_categorical_dependent_variable {
    my ( $self, $c ) = @_;

    my $pheno_file = $self->trial_phenotype_file($c);
    my $header     = ( read_file( $pheno_file, { binmode => ':utf8' } ) )[0];
    my @headers    = split( /\t/, $header );

    $c->controller('solGS::Trait')
      ->get_trait_details( $c, $c->stash->{trait_id} );
    my $trait_abbr = $c->stash->{trait_abbr};

    my $trait_idx = firstidx { $_ eq $trait_abbr } @headers;
    my $trait_col = $trait_idx + 1;

    my $trait_values = `cut -f $trait_col $pheno_file 2>&1`;
    $trait_values =~ s/$trait_abbr|\n//g;
    my @trait_values = split( /\t/, $trait_values );

    my $categorical = all { $_ =~ /[A-Za-z]/ } @trait_values;

    return $categorical;

}

sub check_anova_output {
    my ( $self, $c ) = @_;

    $self->anova_table_file($c);
    my $html_file = $c->stash->{anova_table_html_file};

    my $exists = -s $html_file ? 1 : 0;

    return $exists;

}

sub prepare_response {
    my ( $self, $c ) = @_;

    $self->anova_table_file($c);
    my $anova_txt_file  = $c->stash->{anova_table_txt_file};
    my $anova_html_file = $c->stash->{anova_table_html_file};

    if ( -s $anova_html_file ) {
        $self->anova_model_file($c);
        my $model_file = $c->stash->{anova_model_file};

        $self->adj_means_file($c);
        my $means_file = $c->stash->{adj_means_file};

        $self->anova_diagnostics_file($c);
        my $diagnostics_file = $c->stash->{anova_diagnostics_file};

        my $dir = 'anova';
        $anova_txt_file = $c->controller('solGS::Files')
          ->copy_to_tempfiles_subdir( $c, $anova_txt_file, $dir );
        $model_file = $c->controller('solGS::Files')
          ->copy_to_tempfiles_subdir( $c, $model_file, $dir );
        $means_file = $c->controller('solGS::Files')
          ->copy_to_tempfiles_subdir( $c, $means_file, $dir );
        $diagnostics_file = $c->controller('solGS::Files')
          ->copy_to_tempfiles_subdir( $c, $diagnostics_file, $dir );

        $c->stash->{rest}{anova_table_html_file} =
          read_file( $anova_html_file, { binmode => ':utf8' } );
        $c->stash->{rest}{anova_table_txt_file}       = $anova_txt_file;
        $c->stash->{rest}{anova_model_file}       = $model_file;
        $c->stash->{rest}{adj_means_file}         = $means_file;
        $c->stash->{rest}{anova_diagnostics_file} = $diagnostics_file;

        # Read persisted outlier count from the count file
        my $outliers = $self->_read_outlier_count_file($c);
        $c->stash->{rest}{outliers_excluded} = $outliers;
    }
    else {
        $self->anova_error_file($c);
        my $error_file = $c->stash->{anova_error_file};

        my $error = read_file( $error_file, { binmode => ':utf8' } );
        $c->stash->{rest}{Error} = $error;
    }

}

sub run_anova {
    my ( $self, $c ) = @_;

    $self->anova_query_jobs_file($c);
    $c->stash->{prerequisite_jobs} = $c->stash->{anova_query_jobs_file};

    $self->anova_r_jobs_file($c);
    $c->stash->{dependent_jobs} = $c->stash->{anova_r_jobs_file};

    $c->controller('solGS::AsyncJob')->run_async($c);

}

sub run_anova_single_core {
    my ( $self, $c ) = @_;

    $self->anova_query_jobs($c);
    my $queries = $c->stash->{anova_query_jobs};

    $self->anova_r_jobs($c);
    my $r_jobs = $c->stash->{anova_r_jobs};

    foreach my $job (@$queries) {
        $c->controller('solGS::AsyncJob')->submit_job_cluster( $c, $job );
    }

    foreach my $job (@$r_jobs) {
        $c->controller('solGS::AsyncJob')->submit_job_cluster( $c, $job );
    }

}

sub run_anova_multi_cores {
    my ( $self, $c ) = @_;

    $self->anova_query_jobs_file($c);
    $c->stash->{prerequisite_jobs} = $c->stash->{anova_query_jobs_file};

    $self->anova_r_jobs_file($c);
    $c->stash->{dependent_jobs} = $c->stash->{anova_r_jobs_file};

    $c->controller('solGS::AsyncJob')->run_async($c);

}

sub anova_r_jobs {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $self->anova_input_files($c);
    my $input_file = $c->stash->{anova_input_files};

    $self->anova_output_files($c);
    my $output_file = $c->stash->{anova_output_files};

    $c->stash->{analysis_tempfiles_dir} = $c->stash->{anova_temp_dir};

    $c->stash->{input_files}  = $input_file;
    $c->stash->{output_files} = $output_file;
    $c->stash->{r_temp_file}  = "anova-${trial_id}-${trait_id}";
    $c->stash->{r_script}     = 'R/solGS/anova.r';

    $c->controller('solGS::AsyncJob')->get_cluster_r_job_args($c);
    my $jobs = $c->stash->{cluster_r_job_args};

    if ( reftype $jobs ne 'ARRAY' ) {
        $jobs = [$jobs];
    }

    $c->stash->{anova_r_jobs} = $jobs;

}

sub anova_r_jobs_file {
    my ( $self, $c ) = @_;

    $self->anova_r_jobs($c);
    my $jobs = $c->stash->{anova_r_jobs};

    my $temp_dir  = $c->stash->{anova_temp_dir};
    my $jobs_file = $c->controller('solGS::Files')
      ->create_tempfile( $temp_dir, 'anova-r-jobs-file' );

    nstore $jobs, $jobs_file
      or croak "anova r jobs : $! serializing anova r jobs to $jobs_file";

    $c->stash->{anova_r_jobs_file} = $jobs_file;

}

sub anova_query_jobs {
    my ( $self, $c ) = @_;

    $self->create_anova_phenotype_data_query_jobs($c);
    my $jobs = $c->stash->{anova_pheno_query_jobs};

    if ( reftype $jobs ne 'ARRAY' ) {
        $jobs = [$jobs];
    }

    $c->stash->{anova_query_jobs} = $jobs;
}

sub anova_query_jobs_file {
    my ( $self, $c ) = @_;

    $self->anova_query_jobs($c);
    my $jobs = $c->stash->{anova_query_jobs};

    if ( $jobs->[0] ) {
        my $temp_dir  = $c->stash->{anova_temp_dir};
        my $jobs_file = $c->controller('solGS::Files')
          ->create_tempfile( $temp_dir, 'anova-query-jobs-file' );

        nstore $jobs, $jobs_file
          or croak
          "anova query jobs : $! serializing anova query jobs to $jobs_file";

        $c->stash->{anova_query_jobs_file} = $jobs_file;
    }

}

sub create_anova_phenotype_data_query_jobs {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{pop_id} || $c->stash->{trial_id};
    $c->controller('solGS::AsyncJob')
      ->get_trials_phenotype_query_jobs_args( $c, [$trial_id] );
    my $jobs = $c->stash->{trials_phenotype_query_jobs_args};

    if ( reftype $jobs ne 'ARRAY' ) {
        $jobs = [$jobs];
    }

    $c->stash->{anova_pheno_query_jobs} = $jobs;

}

sub copy_pheno_file_to_anova_dir {
    my ( $self, $c ) = @_;

    my $pheno_file  = $self->trial_phenotype_file($c);
    my $anova_cache = $c->stash->{anova_cache_dir};

    $c->stash->{phenotype_file} =
      $c->controller('solGS::Files')->copy_file( $pheno_file, $anova_cache );

}

sub anova_input_files {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    # Copy the shared phenotype file to the ANOVA cache dir, then
    # filter outliers from the copy — so other solGS tools keep the
    # original unfiltered file.
    my $shared_pheno_file = $self->trial_phenotype_file($c);
    my $anova_cache       = $c->stash->{anova_cache_dir};
    my $pheno_file        = $shared_pheno_file;

    if (-s $shared_pheno_file && $anova_cache) {
        my $filtered_name = "phenotype_data_filtered_${trial_id}.tsv";
        my $filtered_path = catfile($anova_cache, $filtered_name);

        copy($shared_pheno_file, $filtered_path)
            or croak "anova: cannot copy phenotype file: $!";

        my $excluded = $self->_filter_outliers_from_phenofile(
            $c, $filtered_path
        );

        # Persist outlier count so prepare_response can read it
        # across separate HTTP requests
        if ($excluded > 0) {
            $self->_write_outlier_count_file($c, $excluded);
        }

        $pheno_file = $filtered_path;
    }

    $self->anova_traits_file($c);
    my $traits_file = $c->stash->{anova_traits_file};

    $c->controller("solGS::Files")->phenotype_metadata_file($c);
    my $metadata_file = $c->stash->{phenotype_metadata_file};

    my $file_list = join( "\t", $pheno_file, $traits_file, $metadata_file );

    my $tmp_dir = $c->stash->{anova_temp_dir};
    my $name    = "anova_input_files_${trial_id}_${trait_id}";
    my $tempfile =
      $c->controller('solGS::Files')->create_tempfile( $tmp_dir, $name );
    write_file( $tempfile, { binmode => ':utf8' }, $file_list );

    $c->stash->{anova_input_files} = $tempfile;

}

sub anova_traits_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $traits   = $c->stash->{trait_abbr};

    my $tmp_dir = $c->stash->{anova_temp_dir};
    my $name    = "anova_traits_file_${trial_id}";
    my $traits_file =
      $c->controller('solGS::Files')->create_tempfile( $tmp_dir, $name );
    write_file( $traits_file, { binmode => ':utf8' }, $traits );

    $c->stash->{anova_traits_file} = $traits_file;

}

sub anova_output_files {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $self->anova_table_file($c);
    $self->anova_model_file($c);
    $self->adj_means_file($c);
    $self->anova_diagnostics_file($c);
    $self->anova_error_file($c);

    my @files = $c->stash->{anova_table_file};

    my $file_list = join( "\t",
        $c->stash->{anova_model_file},
        $c->stash->{anova_table_html_file},
        $c->stash->{anova_table_txt_file},
        $c->stash->{adj_means_file},
        $c->stash->{anova_diagnostics_file},
        $c->stash->{anova_error_file},
    );

    my $tmp_dir = $c->stash->{anova_temp_dir};
    my $name    = "anova_output_files_${trial_id}_${trait_id}";
    my $tempfile =
      $c->controller('solGS::Files')->create_tempfile( $tmp_dir, $name );
    write_file( $tempfile, { binmode => ':utf8' }, $file_list );

    $c->stash->{anova_output_files} = $tempfile;

}

sub anova_table_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->stash->{cache_dir} = $c->stash->{anova_cache_dir};

    my $cache_data = {
        key       => "anova_table_html_${trial_id}_${trait_id}",
        file      => "anova_table_html_${trial_id}_${trait_id}",
        ext       => 'html',
        stash_key => "anova_table_html_file"
    };

    $c->controller('solGS::Files')->cache_file( $c, $cache_data );

    $c->stash->{cache_dir} = $c->stash->{anova_cache_dir};

    $cache_data = {
        key       => "anova_table_txt_${trial_id}_${trait_id}",
        file      => "anova_table_txt_${trial_id}_${trait_id}",
         ext      => 'txt',
        stash_key => "anova_table_txt_file"
    };

    $c->controller('solGS::Files')->cache_file( $c, $cache_data );

}

sub anova_diagnostics_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->stash->{cache_dir} = $c->stash->{anova_cache_dir};

    my $cache_data = {
        key       => "anova_diagnosics_${trial_id}_${trait_id}",
        file      => "anova_diagnostics_${trial_id}_${trait_id}",
        ext       => '.png',
        stash_key => "anova_diagnostics_file"
    };

    $c->controller('solGS::Files')->cache_file( $c, $cache_data );

}

sub anova_model_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->stash->{cache_dir} = $c->stash->{anova_cache_dir};

    my $cache_data = {
        key       => "anova_model_${trial_id}_${trait_id}",
        file      => "anova_model_${trial_id}_${trait_id}",
        stash_key => "anova_model_file"
    };

    $c->controller('solGS::Files')->cache_file( $c, $cache_data );

}

sub anova_error_file {
    my ( $self, $c ) = @_;

    $c->stash->{file_id} = $c->stash->{trial_id} . '_' . $c->stash->{trait_id};
    $c->stash->{cache_dir}     = $c->stash->{anova_cache_dir};
    $c->stash->{analysis_type} = 'anova';

    $c->controller('solGS::Files')->analysis_error_file($c);

}

sub adj_means_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};

    $c->stash->{cache_dir} = $c->stash->{anova_cache_dir};

    my $cache_data = {
        key       => "adj_means_${trial_id}_${trait_id}",
        file      => "adj_means_${trial_id}_${trait_id}",
        stash_key => "adj_means_file"
    };

    $c->controller('solGS::Files')->cache_file( $c, $cache_data );

}

# Replace outlier-marked phenotype values with NA in the phenotype
# data file.  This keeps the row structure intact (blocks, reps) so
# the mixed-model ANOVA handles missing data gracefully.
sub _filter_outliers_from_phenofile {
    my ( $self, $c, $pheno_file ) = @_;

    return 0 unless $pheno_file && -s $pheno_file;

    my $trial_id = $c->stash->{trial_id};
    my $schema   = $self->schema($c);

    # Resolve the cvterm_id for the outlier property type
    my $outlier_type_id = SGN::Model::Cvterm
        ->get_cvterm_row($schema, 'phenotype_outlier', 'phenotype_property')
        ->cvterm_id();

    # Find all (observationunit_uniquename, trait_name) pairs that are
    # marked as outliers for this trial.  The query traverses:
    #   phenotypeprop -> phenotype -> nd_experiment_phenotype
    #     -> nd_experiment_stock -> stock (observationunit)
    #   phenotype -> cvterm (trait)
    my $dbh = $schema->storage->dbh();
    my $sth = $dbh->prepare(qq{
        SELECT s.uniquename  AS plot_name,
               (((cvt.name || '|') || db.name || ':') || dbx.accession) AS trait_full
        FROM phenotypeprop pp
        JOIN phenotype p       ON pp.phenotype_id = p.phenotype_id
        JOIN nd_experiment_phenotype nep ON nep.phenotype_id = p.phenotype_id
        JOIN nd_experiment_stock nes     ON nes.nd_experiment_id = nep.nd_experiment_id
        JOIN stock s            ON s.stock_id = nes.stock_id
        JOIN cvterm cvt         ON cvt.cvterm_id = p.cvalue_id
        JOIN dbxref dbx         ON dbx.dbxref_id = cvt.dbxref_id
        JOIN db                 ON db.db_id = dbx.db_id
        JOIN nd_experiment_project nexp ON nexp.nd_experiment_id = nep.nd_experiment_id
        WHERE pp.type_id = ?
          AND nexp.project_id = ?
    });
    $sth->execute($outlier_type_id, $trial_id);

    # Build a lookup: { plot_uniquename }{ trait_full_name } = 1
    my %outlier_lookup;
    while (my ($plot_name, $trait_full) = $sth->fetchrow_array()) {
        $outlier_lookup{$plot_name}{$trait_full} = 1;
    }

    return 0 unless keys %outlier_lookup;

    # Read the TSV file and blank out outlier cells
    my @lines = read_file($pheno_file, { binmode => ':utf8' });
    return 0 unless @lines;

    my $header = shift @lines;
    chomp $header;
    my @headers = split(/\t/, $header);

    # Column indices for the observationUnitName (col 22, 0-indexed)
    # and the start of trait columns (after notes/metadata columns).
    # The header layout from PhenotypeMatrix / solGS pipeline:
    #   0:studyYear ... 22:observationUnitName ... 29+:traits...
    my $obs_unit_col_idx;
    my %trait_col_indices;  # trait_full_name => column_index

    for my $i (0 .. $#headers) {
        if ($headers[$i] eq 'observationUnitName') {
            $obs_unit_col_idx = $i;
        }
        # Trait columns contain '|' (e.g. "Grain yield|CO_321:0001218")
        elsif ($headers[$i] =~ /\|/) {
            $trait_col_indices{ $headers[$i] } = $i;
        }
    }

    # If the file format doesn't match expectations, skip filtering
    return 0 unless defined $obs_unit_col_idx && keys %trait_col_indices;

    my $excluded_count = 0;

    for my $line (@lines) {
        chomp $line;
        my @cols = split(/\t/, $line, -1);  # preserve empty trailing fields

        my $plot_name = $cols[$obs_unit_col_idx] // '';
        next unless exists $outlier_lookup{$plot_name};

        for my $trait_name (keys %{ $outlier_lookup{$plot_name} }) {
            if (exists $trait_col_indices{$trait_name}) {
                my $idx = $trait_col_indices{$trait_name};
                # Only blank out if there's actually a value
                if (defined $cols[$idx] && $cols[$idx] ne '' && $cols[$idx] ne 'NA') {
                    $cols[$idx] = 'NA';
                    $excluded_count++;
                }
            }
        }

        $line = join("\t", @cols);
    }

    # Rewrite the file only if we actually excluded something
    if ($excluded_count > 0) {
        my $content = $header . "\n" . join("\n", @lines) . "\n";
        write_file($pheno_file, { binmode => ':utf8' }, $content);
    }

    return $excluded_count;
}

# Persist the outlier exclusion count to a file in the ANOVA cache
# so the response endpoint (a separate HTTP request) can read it.
sub _write_outlier_count_file {
    my ( $self, $c, $count ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};
    my $cache    = $c->stash->{anova_cache_dir};

    return unless $cache;

    my $file = catfile($cache, "outlier_count_${trial_id}_${trait_id}.txt");
    write_file($file, { binmode => ':utf8' }, $count);
}

# Read the persisted outlier count.
sub _read_outlier_count_file {
    my ( $self, $c ) = @_;

    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->stash->{trait_id};
    my $cache    = $c->stash->{anova_cache_dir};

    return 0 unless $cache;

    my $file = catfile($cache, "outlier_count_${trial_id}_${trait_id}.txt");
    return 0 unless -s $file;

    my $count = read_file($file, { binmode => ':utf8' });
    chomp $count;
    return looks_like_number($count) ? $count : 0;
}

sub schema {
    my ( $self, $c ) = @_;

    return $c->dbic_schema("Bio::Chado::Schema");

}

sub begin : Private {
    my ( $self, $c ) = @_;

    $c->controller('solGS::Files')->get_solgs_dirs($c);

}

__PACKAGE__->meta->make_immutable;

1;
