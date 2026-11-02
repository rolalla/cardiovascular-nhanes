# NHANES 2017-2018: survey-weighted systolic BP across BMI categories
# Run from project root: Rscript scripts/05_bmi_category_analysis.R
# Descriptive group estimates, NOT adjusted causal contrasts.

# Locate the user's R library when installed outside Program Files (Windows).
user_home <- Sys.getenv('USERPROFILE', unset=path.expand('~'))
user_lib <- file.path(user_home, 'R', 'library')
if (dir.exists(user_lib)) .libPaths(c(user_lib, .libPaths()))
if (!requireNamespace('survey', quietly=TRUE)) {
  stop('Missing R package survey. Install it in your user library before running.')
}
library(survey)
options(survey.lonely.psu = 'adjust')

input <- file.path('data', 'processed', 'cardiovascular_data.csv')
if (!file.exists(input)) stop('Missing ', input, '. Run notebook 01 first.')
d <- read.csv(input, stringsAsFactors=FALSE, check.names=FALSE, fileEncoding='UTF-8')
needed <- c('bmi','sbp_mean','mec_weight','SDMVSTRA','SDMVPSU')
missing <- setdiff(needed, names(d))
if (length(missing)) stop('Missing columns: ', paste(missing, collapse=', '))

# Same adult dataset used in notebook 01; do not alter values or discard observations
# outside the relevant variables. Exclude zero/invalid survey weights or design IDs.
d <- subset(d, is.finite(mec_weight) & mec_weight > 0 &
               !is.na(SDMVSTRA) & !is.na(SDMVPSU))

# Standard adult BMI categories; underweight <18.5, normal [18.5,25),
# overweight [25,30), obesity >=30. Invalid/missing BMI remains NA.
d$bmi_category <- cut(d$bmi,
  breaks=c(-Inf,18.5,25,30,Inf), right=FALSE,
  labels=c('Underweight','Normal weight','Overweight','Obesity'))
d$bmi_category <- factor(d$bmi_category,
  levels=c('Underweight','Normal weight','Overweight','Obesity'))

# Create survey design using all eligible adult sample members before domain selection.
design <- svydesign(ids=~SDMVPSU, strata=~SDMVSTRA,
                    weights=~mec_weight, nest=TRUE, data=d)
# The analysis is restricted to participants with measured SBP and BMI.
analysis <- subset(design, !is.na(bmi_category) & is.finite(sbp_mean))

# Counts are UNWEIGHTED people; do not confuse them with weighted population counts.
count <- as.data.frame(table(analysis$variables$bmi_category))
names(count) <- c('bmi_category','n_unweighted')
count$bmi_category <- as.character(count$bmi_category)

# Survey-weighted means with design-based SE and confidence intervals.
means <- svyby(~sbp_mean, ~bmi_category, analysis, svymean,
               na.rm=TRUE, vartype=c('se','ci'), drop.empty.groups=FALSE)
tab <- as.data.frame(means)
# Keep explicit validated field names for Power BI.
if (!all(c('bmi_category','sbp_mean','se','ci_l','ci_u') %in% names(tab))) {
  stop('Unexpected survey::svyby column names: ', paste(names(tab), collapse=', '))
}
tab <- merge(tab[,c('bmi_category','sbp_mean','se','ci_l','ci_u')],
             count, by='bmi_category', all.x=TRUE, sort=FALSE)
tab$bmi_order <- match(as.character(tab$bmi_category),
                       c('Underweight','Normal weight','Overweight','Obesity'))
tab <- tab[order(tab$bmi_order), c('bmi_category','bmi_order','n_unweighted',
                                 'sbp_mean','se','ci_l','ci_u')]
if (any(tab$n_unweighted < 30, na.rm=TRUE)) {
  warning('One or more categories have fewer than 30 observations: interpret cautiously.')
}

outdir <- file.path('data', 'processed')
dir.create(outdir, recursive=TRUE, showWarnings=FALSE)
outfile <- file.path(outdir, 'r_validated_bmi_groups.csv')
write.csv(tab, outfile, row.names=FALSE, na='')
cat('Unweighted N for each BMI category and survey-weighted SBP estimates:\n')
print(tab, row.names=FALSE)
cat('\nSurvey design df:', degf(analysis), '\n')
cat('Saved:', normalizePath(outfile), '\n')
cat('These are descriptive, unadjusted group comparisons. The separate regression BMI coefficient is adjusted for age group and sex.\n')
