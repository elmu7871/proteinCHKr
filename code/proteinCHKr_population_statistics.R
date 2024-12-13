 # this document is an accessory of proteinCHKr.Rmd. In this document, I am generating population statistics for the whole human proteome's CHK content.

# this is a separate document so i can run the main doco without having to query 23214 genes + ~13000 proteins to ensembl (~12min runtime) every time... for their sake and mine. The purpose is to have all dependent files pre-made so that I can put proteinCHKr in one script without unnecessarily remaking files every time it runs. i'll eventually turn this into a .R file rather than .Rmd

# this document creates proteomeStats.rds/csv, sample_Hsa_peptideseqs.Rds, sample_Hsa_peptides.Rds, popoutput.rds/csv, and gene2hgnc.rds.

library(dplyr)
library(readr)
library(here)
library(biomaRt)
library(tidyverse)
library(conflicted)
library(stringr)
library(Hmisc)

mart <- useMart(biomart='ENSEMBL_MART_ENSEMBL', dataset='hsapiens_gene_ensembl')
gene2hgnc <- getBM(attributes=c('ensembl_gene_id', 'hgnc_symbol'),mart=mart) 
saveRDS(gene2hgnc, file = here("proteinCHKr", "accessories", "gene2hgnc.rmd"))

mart <- useMart(biomart='ENSEMBL_MART_ENSEMBL', 
                dataset='hsapiens_gene_ensembl')

allcodingensemblids <- getBM(attributes=c('ensembl_gene_id', 'gene_biotype'),mart=mart) %>%
  dplyr::filter(gene_biotype == "protein_coding") %>%
  dplyr::select(!gene_biotype) %>%
  as.matrix()

randomnumbers <- sample(1:length(allcodingensemblids), 3000, replace = F)

chunk <- function(x, n) {mapply(function(a, b) (x[a:b]), seq.int(from=1, to=length(x), by=n), pmin(seq.int(from=1, to=length(x), by=n)+(n-1), length(x)), SIMPLIFY=FALSE)
} # found this on stackoverflow, thanks verbamour

chunks <- chunk(randomnumbers, n = 500)

# cordoning off this Big Chunk because it takes ten+ minutes to run and i don't want to run it by accident
start <- Sys.time()
allcodingensemblpeptides <- list()
for(i in 1:length(test)) {
  allcodingensemblpeptides[[i]] <- getSequence(id = allcodingensemblids[chunks[[i]]],
                                               type = "ensembl_gene_id",
                                               seqType = "peptide",
                                               mart = mart) %>%
    dplyr::filter(peptide != "Sequence unavailable")
}
end <- Sys.time()
runtime <- end - start
print(runtime) # only 10 minutes! haha

# there are 23214 coding genes with known protein sequences returned by ensembl 20240412. I tried retrieving all 23214 available genes' peptide sequences, but ensembl predictably timed out. Instead, I've sampled 3000 random genes to achieve <2% margin of error and 95% confidence. ensembl takes more than 5 minutes (timeout limit) to return 1000 genes' peptide sequences, so i've divided it into three batches of 500

samplepeptides <- rbind(
  as.data.frame(allcodingensemblpeptides[[1]]),
  as.data.frame(allcodingensemblpeptides[[2]]),
  as.data.frame(allcodingensemblpeptides[[3]]),
  as.data.frame(allcodingensemblpeptides[[4]]),
  as.data.frame(allcodingensemblpeptides[[5]]),
  as.data.frame(allcodingensemblpeptides[[6]])
)

colnames(samplepeptides)[1] <- "peptide"

# save in an RDS so i don't have to wait 10 minutes every time i want to use this data during development
saveRDS(samplepeptides, file = here("proteinCHKr", "accessories", "sample_Hsa_peptideseqs.Rds")) 

samplepeptides <- readRDS(file = here("proteinCHKr", "accessories", "sample_Hsa_peptideseqs.Rds"))

for(i in 1:nrow(samplepeptides)) {
  samplepeptides$length[i] <- nchar(samplepeptides$peptide[i])
}

for(i in 1:nrow(samplepeptides)) {
  samplepeptides$chk[i] <- sum(str_count(string = samplepeptides$peptide[i], pattern = c("C", "H", "K")))
}

for (i in 1:nrow(samplepeptides)) {
  samplepeptides$percentCHK[i] <- (samplepeptides$chk[i] / samplepeptides$length[i]) * 100
  
}
# saveRDS(samplepeptides, file = here("proteinCHKr", "accessories", "samplepeptides_processed.rds"))

popoutput <- samplepeptides %>%
  group_by(ensembl_gene_id) %>%
  summarise(percentCHKmean = mean(percentCHK))

# I want to calculate hhow many standard deviations from the mean a user-queried gene's CHK content is. If it's more than two, I'll mark it with a note in the output dataframe.
proteomeStats <- data.frame(
  "mean" = mean(popoutput$percentCHKmean),
  "sd" = sd(popoutput$percentCHKmean),
  "upper" = (mean(popoutput$percentCHKmean) + 2*sd(popoutput$percentCHKmean)),
  "lower" = (mean(popoutput$percentCHKmean) - 2*sd(popoutput$percentCHKmean))
)

for (i in 1:nrow(popoutput)) {
  if (popoutput$percentCHKmean[i] > proteomeStats$upper) {
    popoutput$above[i] <- TRUE
  } else {
    popoutput$above[i] <- FALSE
  }
}

for (i in 1:nrow(popoutput)) {
  if (popoutput$percentCHKmean[i] < proteomeStats$lower) {
    popoutput$below[i] <- TRUE
  } else {
    popoutput$below[i] <- FALSE
  }
}

gene2hgnc <- readRDS(file = here("proteinCHKr", "accessories", "gene2hgnc.rmd"))

popoutput <- popoutput %>% left_join(gene2hgnc, by = "ensembl_gene_id")

saveRDS(popoutput, file = here("proteinCHKr", "accessories", "popoutput.rds"))
write_csv(popoutput, file = here("proteinCHKr", "results", "popoutput.rds"))

saveRDS(proteomeStats, file = here("proteinCHKr", "accessories", "proteomeStats.rds"))
write_csv(proteomeStats, file = here("proteinCHKr", "results", "proteomeStats.rds"))