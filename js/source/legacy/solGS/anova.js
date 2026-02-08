/**
 * single trial ANOVA analysis
 * Isaak Y Tecle <iyt2@cornell.edu>
 *
 */

var solGS = solGS || function solGS() { };

solGS.anova = {
  canvas: "#anova_canvas",
  msgDiv: "#anova_message",
  runDiv: "#run_anova",
  anovaTraitsDiv: "#anova_select_a_trait_div",
  anovaTraitsSelectMenuId: "#anova_select_traits",

  checkTrialDesign: function () {
    var trialId = this.getTrialId();
    var args = JSON.stringify({ trial_id: trialId });

    var trialDesign = jQuery.ajax({
      type: "POST",
      dataType: "json",
      data: { arguments: args },
      url: "/anova/check/design/",
    });

    return trialDesign;
  },

  anovaAlert: function (msg) {
    var jobSubmit = '<div id= "anova_msg">' + msg + "</div>";

    jQuery(jobSubmit).appendTo("body");

    jQuery("#anova_msg").dialog({
      modal: true,
      title: "Alert",
      buttons: {
        OK: {
          click: function () {
            jQuery(this).dialog("close");
          },
          class: "btn btn-success",
          text: "OK",
        },
      },
    });
  },

  queryPhenoData: function (traitId) {
    var trialId = this.getTrialId();
    var args = JSON.stringify({ trial_id: trialId, trait_id: traitId });

    var phenoData = jQuery.ajax({
      type: "POST",
      dataType: "json",
      data: { arguments: args },
      url: "/anova/phenotype/data/",
    });

    return phenoData;
  },

  showMessage: function (msg) {
    jQuery(this.msgDiv).html(msg);
  },

  runAnovaAnalysis: function (traits) {
    var trialId = this.getTrialId();
    var captions = jQuery("#anova_table table").find("caption").text();
    var analyzedTraits = captions.replace(/ANOVA result:/g, " ");

    var traitAbbr = traits.trait_abbr;

    if (analyzedTraits.match(traitAbbr) == null) {
      var args = JSON.stringify({ trial_id: trialId, trait_id: traits.trait_id });

      var anovaAnalysis = jQuery.ajax({
        type: "POST",
        dataType: "json",
        data: { arguments: args },
        url: "/anova/analysis/",
      });

      return anovaAnalysis;
    } else {
      jQuery(this.msgDiv).empty();
      jQuery(this.runDiv).show();
      solGS.anova.clearTraitSelection();
    }
  },

  getAnovaTraits: function () {
    var trialId = this.getTrialId();
    var args = JSON.stringify({ trial_id: trialId });

    var anovaTraits = jQuery.ajax({
      type: "POST",
      dataType: "json",
      data: { arguments: args },
      url: "/anova/traits/list/",
    });

    return anovaTraits;
  },

  populateAnovaMenu: function (traits) {
    var selectId = this.anovaTraitsSelectMenuId;
    var menuDivId = this.anovaTraitsDiv;

    var optionsLabel = "Select a trait";
    var menuClass = "form-control";
    var menu = new SelectMenu(menuDivId, selectId, menuClass, optionsLabel);
    menu.populateMenu(traits)

  },

  clearTraitSelection: function () {
    jQuery("#anova_selected_trait_name").val("");
    jQuery("#anova_selected_trait_id").val("");
  },

  getTrialId: function () {
    var trialId = jQuery("#trial_id").val();

    if (!trialId) {
      trialId = jQuery("#training_pop_id").val();
    }

    return trialId;
  },
};

jQuery(document).ready(function () {
  var url = document.URL;
  var runDiv = solGS.anova.runDiv;
  if (url.match(/\/breeders_toolbox\/trial|breeders\/trial|\/solgs\/population\//)) {
    solGS.anova
      .checkTrialDesign()
      .done(function (designRes) {
        if (designRes.Error) {
          solGS.anova.showMessage(designRes.Error);
          jQuery(runDiv).hide();
        } else {
          solGS.anova
            .getAnovaTraits()
            .done(function (traitsRes) {
              var traits = traitsRes.anova_traits;

              if (traits.length) {
                solGS.anova.populateAnovaMenu(traits);
                jQuery(runDiv).show();
              } else {
                solGS.anova.showMessage("This trial has no phenotyped traits.");
                jQuery(runDiv).hide();
              }
            })
            .fail(function () {
              solGS.anova.showMessage("Error occured listing anova traits.");
              jQuery(runDiv).hide();
            });
        }
      })
      .fail(function () {
        solGS.anova.showMessage("Error occured running the ANOVA.");
        jQuery(runDiv).show();
      });
  }
});

jQuery(document).ready(function () {
  var runDiv = solGS.anova.runDiv;
  var canvas = solGS.anova.canvas;

  jQuery(document).on("click", runDiv, function () {
    var traitId = jQuery("#anova_selected_trait_id").val();
    if (traitId) {
      jQuery(runDiv).hide();
      solGS.anova.showMessage("Please wait...querying the database for the trait data...");
      jQuery(`${canvas} .multi-spinner-container`).show();

      solGS.anova.queryPhenoData(traitId).done(function (queryRes) {
        if (queryRes.Error) {
          solGS.anova.showMessage(queryRes.Error);
          jQuery(runDiv).show();
          jQuery(`${canvas} .multi-spinner-container`).hide();
        } else {
          var traitsAbbrs = queryRes.traits_abbrs;
          traitsAbbrs = JSON.parse(traitsAbbrs);
          solGS.anova.showMessage("Validated trait data...now running ANOVA...");

          solGS.anova
            .runAnovaAnalysis(traitsAbbrs)
            .done(function (analysisRes) {
              if (analysisRes.Error) {
                jQuery(`${canvas} .multi-spinner-container`).hide();
                jQuery(solGS.anova.msgDiv).empty();
                solGS.anova.showMessage(analysisRes.Error);
                jQuery(runDiv).show();
              } else {
                jQuery(`${canvas} .multi-spinner-container`).hide();
                jQuery(solGS.anova.msgDiv).empty();
                jQuery(runDiv).show();

                var anovaHtmlTable = analysisRes.anova_table_html_file;
                if (anovaHtmlTable) {
                  var anovaTxtFile = analysisRes.anova_table_txt_file;
                  var modelSummaryFile = analysisRes.anova_model_file;
                  var AdjMeansFile = analysisRes.adj_means_file;
                  var diagnosticsFile = analysisRes.anova_diagnostics_file;

                  var AnovaTxtFileName = anovaTxtFile.split("/").pop();
                  var modelSummaryFileName = modelSummaryFile.split("/").pop();
                  var AdjMeansFileName = AdjMeansFile.split("/").pop();
                  var fileNameDiagnostics = diagnosticsFile.split("/").pop();
                  anovaTxtFile =
                    '<a href="' + anovaTxtFile + '" download=' + AnovaTxtFileName + ">Anova table</a>";
                  modelSummaryFile =
                    '<a href="' + modelSummaryFile + '" download=' + modelSummaryFileName + ">Model summary</a>";
                  AdjMeansFile =
                    '<a href="' + AdjMeansFile + '" download=' + AdjMeansFileName + ">Adjusted means</a>";

                  diagnosticsFile =
                    '<a href="' +
                    diagnosticsFile +
                    '" download=' +
                    fileNameDiagnostics +
                    ">Model diagnostics</a>";

                  // Quality Control: show info banner if outliers were excluded
                  var outlierBanner = '';
                  if (analysisRes.outliers_excluded && analysisRes.outliers_excluded > 0) {
                    outlierBanner = '<div class="alert alert-info" style="margin-top:10px">'
                      + '<strong>Quality Control:</strong> '
                      + analysisRes.outliers_excluded
                      + ' outlier value(s) excluded from analysis.'
                      + '</div>';
                  }

                  // QC validation warning: show if trial hasn't been QC-validated
                  var qcWarningBanner = '';
                  if (!analysisRes.qc_validated || analysisRes.qc_validated == 0) {
                    qcWarningBanner = '<div class="alert alert-warning" style="margin-top:10px">'
                      + '<span class="glyphicon glyphicon-exclamation-sign"></span> '
                      + '<strong>QC не проведён</strong> — для этого трайла не выполнена проверка качества данных. '
                      + '<a href="/tools/qualitycontrol" target="_blank">Открыть Quality Control</a>'
                      + '</div>';
                  }

                  jQuery("#anova_table")
                    .prepend(
                      qcWarningBanner +
                      outlierBanner +
                      '<div style="margin-top: 20px">' +
                      anovaHtmlTable +
                      "</div>" +
                      "<br /> <strong>Download:</strong> " +
                      anovaTxtFile +
                      " | " +
                      modelSummaryFile +
                      " | " +
                      diagnosticsFile +
                      " | " +
                      AdjMeansFile +
                      '<div id="adj_means_inline_table" style="margin-top:20px"></div>'
                    )
                    .show();

                  // Fetch and render adjusted means inline
                  var adjMeansUrl = analysisRes.adj_means_file;
                  if (adjMeansUrl) {
                    jQuery.get(adjMeansUrl, function (tsvData) {
                      if (!tsvData || !tsvData.trim()) return;
                      var lines = tsvData.trim().split('\n');
                      if (lines.length < 2) return;

                      // Parse TSV header and rows
                      var sep = lines[0].indexOf('\t') >= 0 ? '\t' : ',';
                      var headers = lines[0].split(sep).map(function (h) { return h.replace(/"/g, '').trim(); });
                      var rows = [];
                      for (var r = 1; r < lines.length; r++) {
                        var cols = lines[r].split(sep).map(function (c) { return c.replace(/"/g, '').trim(); });
                        if (cols.length >= headers.length) rows.push(cols);
                      }

                      if (!rows.length) return;

                      // Build HTML table
                      var html = '<h4 style="color:#2c3e50; margin-top:16px;">Adjusted Means (individual germplasm)</h4>';
                      html += '<table id="adj_means_dt" class="table table-bordered table-striped table-condensed" style="width:100%">';
                      html += '<thead><tr>';
                      headers.forEach(function (h) {
                        html += '<th>' + h + '</th>';
                      });
                      html += '</tr></thead><tbody>';

                      rows.forEach(function (row) {
                        html += '<tr>';
                        row.forEach(function (cell, idx) {
                          // Format numeric columns (skip first which is germplasm name)
                          if (idx > 0 && !isNaN(parseFloat(cell))) {
                            html += '<td style="text-align:right">' + parseFloat(cell).toFixed(2) + '</td>';
                          } else {
                            html += '<td>' + cell + '</td>';
                          }
                        });
                        html += '</tr>';
                      });
                      html += '</tbody></table>';

                      jQuery('#adj_means_inline_table').html(html);

                      // Initialize DataTable for sorting/search if available
                      if (jQuery.fn.DataTable) {
                        jQuery('#adj_means_dt').DataTable({
                          pageLength: 25,
                          order: [[1, 'desc']],
                          language: {
                            search: "\u041f\u043e\u0438\u0441\u043a:",
                            lengthMenu: "\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c _MENU_ \u0437\u0430\u043f\u0438\u0441\u0435\u0439",
                            info: "\u041f\u043e\u043a\u0430\u0437\u0430\u043d\u043e _START_ \u0434\u043e _END_ \u0438\u0437 _TOTAL_",
                            paginate: { previous: "\u2190", next: "\u2192" }
                          }
                        });
                      }

                      // Show baseline info and Save Scores button
                      var baseline = analysisRes.points_score_baseline;
                      var psCount = analysisRes.points_score_count;
                      if (baseline && baseline > 0) {
                        var baselineHtml = '<div style="margin-top:12px; padding:10px; background:#f0f7ff; border-left:4px solid #3498db; border-radius:4px;">'
                          + '<strong>Points Score:</strong> '
                          + '\u0411\u0430\u0437\u043e\u0432\u0430\u044f \u0443\u0440\u043e\u0436\u0430\u0439\u043d\u043e\u0441\u0442\u044c (\u0432\u0435\u0440\u0445\u043d\u0438\u0435 \u2154) = <strong>' + baseline + ' t/ha</strong> = 100 \u0431\u0430\u043b\u043b\u043e\u0432 '
                          + '| \u0413\u0438\u0431\u0440\u0438\u0434\u043e\u0432: ' + psCount
                          + ' <button id="save_points_scores_btn" class="btn btn-primary btn-sm" style="margin-left:15px;">'
                          + '<span class="glyphicon glyphicon-save"></span> \u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u0431\u0430\u043b\u043b\u044b</button>'
                          + '<span id="save_scores_status" style="margin-left:10px;"></span>'
                          + '</div>';
                        jQuery('#adj_means_inline_table').append(baselineHtml);

                        // Save Scores click handler
                        jQuery('#save_points_scores_btn').on('click', function () {
                          var btn = jQuery(this);
                          btn.prop('disabled', true).text('\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u0435...');
                          jQuery('#save_scores_status').html('');

                          var saveArgs = JSON.stringify({
                            trial_id: solGS.anova.getTrialId(),
                            trait_id: traitId
                          });

                          jQuery.ajax({
                            url: '/anova/save_points_scores/',
                            type: 'POST',
                            data: { arguments: saveArgs },
                            dataType: 'json',
                            success: function (res) {
                              if (res.success) {
                                jQuery('#save_scores_status').html(
                                  '<span style="color:green"><span class="glyphicon glyphicon-ok"></span> '
                                  + res.success + '</span>'
                                );
                                btn.text('\u2713 \u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e').addClass('btn-success').removeClass('btn-primary');
                              } else {
                                jQuery('#save_scores_status').html(
                                  '<span style="color:red">' + (res.Error || '\u041e\u0448\u0438\u0431\u043a\u0430') + '</span>'
                                );
                                btn.prop('disabled', false).text('\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u0431\u0430\u043b\u043b\u044b');
                              }
                            },
                            error: function () {
                              jQuery('#save_scores_status').html('<span style="color:red">\u041e\u0448\u0438\u0431\u043a\u0430 \u0441\u0435\u0442\u0438</span>');
                              btn.prop('disabled', false).text('\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u0431\u0430\u043b\u043b\u044b');
                            }
                          });
                        });
                      }
                    });
                  }
                } else {
                  jQuery(`${canvas} .multi-spinner-container`).hide();
                  solGS.anova.showMessage("There is no anova output for this dataset.");
                  jQuery(runDiv).show();
                }
              }
            })
            .fail(function () {
              jQuery(`${canvas} .multi-spinner-container`).hide();
              solGS.anova.showMessage("Error occured running the anova analysis.");
              jQuery(runDiv).show();
            });
        }

        solGS.anova.clearTraitSelection();
      });
    } else {
      var msg = "Please select a trait.";
      solGS.anova.anovaAlert(msg);
    }
  });
});

jQuery(document).ready(function () {
  var anovaTraitsDiv = solGS.anova.anovaTraitsDiv;

  jQuery(anovaTraitsDiv).change(function () {
    var selectedTrait = jQuery("option:selected", this).data("pop");
    jQuery("#anova_selected_trait_name").val(selectedTrait.name);
    jQuery("#anova_selected_trait_id").val(selectedTrait.id);
  });
});
