# Cardiovascular NHANES — design-based validation of notebook 03
# Run from the project root: Rscript scripts/04_validate_survey_models.R
if (!requireNamespace('survey', quietly=TRUE)) {
  stop('Install the survey package first: install.packages("survey")')
}
library(survey)
options(survey.lonely.psu='adjust')

infile <- file.path('data','processed','cardiovascular_data.csv')
if (!file.exists(infile)) stop('Run notebook 01 first; missing: ', infile)
outdir <- file.path('data','processed')
d <- read.csv(infile, stringsAsFactors=FALSE, check.names=FALSE, fileEncoding='UTF-8')
required <- c('sbp_mean','dbp_mean','high_measured_bp','age_group','sex',
              'bmi','mec_weight','SDMVSTRA','SDMVPSU')
missing <- setdiff(required,names(d))
if(length(missing)) stop('Missing columns: ', paste(missing,collapse=', '))
d$age_group <- factor(d$age_group, levels=c('20–39','40–59','60–79','80+'))
d$sex <- factor(d$sex, levels=c('Female','Male'))
d <- subset(d, !is.na(mec_weight) & mec_weight>0 & !is.na(SDMVSTRA) & !is.na(SDMVPSU))
cat('Adults with positive weights and design IDs:',nrow(d),'\n')

# Base survey design: retain all adults so subgroup estimation handles design domains.
design <- svydesign(ids=~SDMVPSU, strata=~SDMVSTRA, weights=~mec_weight,
                    nest=TRUE, data=d)
cat('Full survey design degrees of freedom:',degf(design),'\n')

# Sample-weighted overall estimates (complete observations for each variable)
metrics <- c('sbp_mean','dbp_mean','high_measured_bp')
overall <- do.call(rbind, lapply(metrics, function(nm) {
  obj <- svymean(as.formula(paste0('~',nm)), design, na.rm=TRUE)
  ci <- confint(obj)
  data.frame(metric=nm, estimate=as.numeric(coef(obj)), se=as.numeric(SE(obj)),
             ci_low=ci[1,1],ci_high=ci[1,2])
}))
write.csv(overall,file.path(outdir,'r_validated_overall.csv'),row.names=FALSE)
print(overall, row.names=FALSE)

# Survey-domain mean SBP by age and sex; NA outcomes excluded.
means <- svyby(~sbp_mean, ~age_group+sex, design, svymean,
               na.rm=TRUE, vartype=c('se','ci'), drop.empty.groups=FALSE)
write.csv(as.data.frame(means),file.path(outdir,'r_validated_groups.csv'),row.names=FALSE)
print(means)

# Match the notebook's complete-case regression population as closely as possible.
# Keep the full design and subset, preserving the original PSU/strata structure.
model_design <- subset(design, !is.na(sbp_mean) & !is.na(bmi) &
                       !is.na(age_group) & !is.na(sex))
cat('Regression N:',nrow(model_design$variables),'\n')

# Baseline: BMI + age group + sex. Expanded: group-specific male/female difference.
model_add <- svyglm(sbp_mean ~ bmi + age_group + sex, design=model_design)
model_int <- svyglm(sbp_mean ~ bmi + age_group*sex, design=model_design)

extract <- function(m) {
  co <- coef(m); se <- SE(m); ci <- confint(m)
  data.frame(term=names(co), estimate=as.numeric(co), se=as.numeric(se),
             ci_low=ci[,1],ci_high=ci[,2], row.names=NULL)
}
write.csv(extract(model_add),file.path(outdir,'r_validated_additive_model.csv'),row.names=FALSE)
write.csv(extract(model_int),file.path(outdir,'r_validated_interaction_model.csv'),row.names=FALSE)
cat('\nInteraction model:\n');print(summary(model_int))
cat('\nJoint interaction Wald test:\n')
interaction_test <- regTermTest(model_int, ~age_group:sex, method='Wald')
print(interaction_test)

capture.output(interaction_test,
               file=file.path(outdir,'r_validated_interaction_test.txt'))
cat('\nSaved R validation outputs to:', normalizePath(outdir),'\n')
cat('Compare them with the notebook 03 outputs. Differences in confidence intervals\n')
cat('can reflect different degrees-of-freedom and survey variance conventions.\n')
