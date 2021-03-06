# re-estimate background error from duplex-seq data 
# piece-wise density estimation with Pareto tail and beta distribution
# Chang Xu, 13NOV2017

rm(list=ls())

# find location of the script
# https://stackoverflow.com/questions/46229411/set-the-working-directory-to-the-parent-folder-of-the-script-file-in-r
thisFile <- function() {
    cmdArgs <- commandArgs(trailingOnly = FALSE)
    needle <- "--file="
    match <- grep(needle, cmdArgs)
    if (length(match) > 0) {
        # Rscript
        return(normalizePath(sub(needle, "", cmdArgs[match])))
    } else {
        # 'source'd via R console
        return(normalizePath(sys.frames()[[1]]$ofile))
    }
}
script.dir <- dirname(thisFile())
setwd(script.dir)

library(fitdistrplus)
library(Hmisc)
library(gPdtest)
library(dplyr)
library(laeken)
library(rmutil)

options(stringsAsFactors=F)
set.seed(732017)
nsim <- 50000
select <- dplyr::select
filter <- dplyr::filter

# function to find reverse nucleotide
rev <- function(x){
  if(x=='a') y <- 't'
  else if (x=='c') y <- 'g'
  else if (x=='g') y <- 'c'
  else if (x=='t') y <- 'a'
  else if (x=='A') y <- 'T'
  else if (x=='C') y <- 'G'
  else if (x=='G') y <- 'C'
  else if (x=='T') y <- 'A'
  else y <- 'n'  
  return(y)
}

min.mtDepth <- 1000
pMax <- 0.01
# this file contains HC region (v3.3.2), homozygous reference, filter passed, non-repetitive region sites
bkg1 <- read.delim('bkg.duplex_oneReadPairUMIsDropped.txt', header=T)
bkg2 <- read.delim('bkg.duplex_oneReadPairUMIsIncluded.txt', header=T)

types <- c('AC', 'AG', 'AT', 'CA', 'CG', 'CT', 'GA', 'GC', 'GT', 'TA', 'TC', 'TG')

#####################################################
# excluding 1 read MTs
#####################################################
dat <- bkg1
for(type in types){
  ref <- unlist(strsplit(type, split=''))[1]
  alt <- unlist(strsplit(type, split=''))[2]  
  tmp <- filter(dat, (REF==ref & negStrand > min.mtDepth) | (REF==rev(ref) & posStrand > min.mtDepth)) %>% 
    mutate(counts = eval(parse(text=paste0(ref, '.', alt))),
           all = ifelse(REF==ref, negStrand, posStrand),
           p = counts / all ) %>%
    filter(p < pMax)
  assign(paste0('p', ref, alt), tmp$p)
}

# 8 lower-error subs
tmp <- mutate(dat, sum8 = A.C + C.A + A.T + T.A + C.G + G.C + G.T + T.G, total8 = AllSMT * 2, p8 = sum8 / total8) %>% 
  filter(total8 > 80000 & p8 < .001)
plot(density(tmp$p8))
summary(tmp$p8)


#######################  Beta distribution + Pareto tail  ######################
types4 <- c('AG', 'GA', 'CT', 'TC')

x0.AG <- 1.2e-3
x0.GA <- 1.2e-3
x0.CT <- 5e-4
x0.TC <- 5e-4

ul.AG <- 0.0015
ul.GA <- 0.0025
ul.CT <- 0.0020
ul.TC <- 1

# fit beta distribution; 0's are imputed
x0s <- thetas <- shape1s <- shape2s <- pBetas <- rep(NA, 4)

for(i in 1:4){
  type <- types4[i]
  # fit pareto tails
  ul <- eval(parse(text=paste0('ul.', type)))
  p.tmp <- eval(parse(text=paste0('p', type)))
  x0 <- eval(parse(text=paste0('x0.', type)))
  pareto.theta <- paretoTail(p.tmp[p.tmp < ul], x0 = x0)$theta
  # fit beta distribution
  p.min <- min(p.tmp[p.tmp > 0])
  p.tmp1 <- ifelse(p.tmp == 0, runif(1, 0, p.min), p.tmp)
  fit <- fitdist(p.tmp1, distr='beta', method='mle')
  shape1 <- fit$estimate[1]
  shape2 <- fit$estimate[2]
  
  # simulate beta's
  tmp <- rbeta(5*nsim, shape1, shape2)
  tmp <- tmp[tmp <= x0]
  p.beta <- sum(p.tmp <= x0)/length(p.tmp)
  r.beta <- sample(tmp, round(nsim*p.beta))
  
  # simulate pareto's; remove extremely large data points
  r.pare <- x0 * runif(round(nsim * (1-p.beta)))^(-1/pareto.theta)
  p.max <- max(p.tmp)
  r.pare <- ifelse(r.pare <= ul, r.pare, runif(1, 0, p.max))
  assign(paste0('r.', tolower(type)), c(r.beta, r.pare)) 
  
  # save parameters
  x0s[i] <- x0
  thetas[i] <- pareto.theta
  shape1s[i] <- shape1
  shape2s[i] <- shape2
  pBetas[i] <- p.beta
}

parameters.exclude_1rpUMI <- data.frame(types4, x0s, thetas, shape1s, shape2s, pBetas)
colnames(parameters.exclude_1rpUMI) <- c('type', 'x0', 'theta', 'shape1', 'shape2', 'pBeta')
r.exc1.ag <- r.ag
r.exc1.ga <- r.ga
r.exc1.ct <- r.ct
r.exc1.tc <- r.tc


#####################################################
# including 1 read MTs
#####################################################
dat <- bkg2
for(type in types){
  ref <- unlist(strsplit(type, split=''))[1]
  alt <- unlist(strsplit(type, split=''))[2]  
  tmp <- filter(dat, (REF==ref & negStrand > min.mtDepth) | (REF==rev(ref) & posStrand > min.mtDepth)) %>% 
    mutate(counts = eval(parse(text=paste0(ref, '.', alt))),
           all = ifelse(REF==ref, negStrand, posStrand),
           p = counts / all ) %>%
    filter(p < pMax)
  assign(paste0('p', ref, alt), tmp$p)
}

#####################################
# paretoQPlot(pTC)
x0.AG <- 0.0025
x0.GA <- 0.0025
x0.CT <- 0.0020
x0.TC <- 0.0020

ul.AG <- 0.040
ul.GA <- 0.025
ul.CT <- 0.020
ul.TC <- 0.030

x0s <- thetas <- shape1s <- shape2s <- pBetas <- rep(NA, 4)

# fit beta distribution; 0's are imputed
for(i in 1:4){
  type <- types4[i]
  # fit pareto tails
  ul <- eval(parse(text=paste0('ul.', type)))
  p.tmp <- eval(parse(text=paste0('p', type)))
  x0 <- eval(parse(text=paste0('x0.', type)))
  pareto.theta <- paretoTail(p.tmp[p.tmp < ul], x0 = x0)$theta
  # fit beta distribution
  p.min <- min(p.tmp[p.tmp > 0])
  p.tmp1 <- ifelse(p.tmp == 0, runif(1, 0, p.min), p.tmp)
  fit <- fitdist(p.tmp1, distr='beta', method='mle')
  shape1 <- fit$estimate[1]
  shape2 <- fit$estimate[2]
  
  # simulate beta's
  tmp <- rbeta(5*nsim, shape1, shape2)
  tmp <- tmp[tmp <= x0]
  p.beta <- sum(p.tmp <= x0)/length(p.tmp)
  r.beta <- sample(tmp, round(nsim*p.beta))
  
  # simulate pareto's; remove extremely large data points
  r.pare <- x0 * runif(round(nsim * (1-p.beta)))^(-1/pareto.theta)
  p.max <- max(p.tmp)
  r.pare <- ifelse(r.pare <= ul, r.pare, runif(1, 0, p.max))
  assign(paste0('r.', tolower(type)), c(r.beta, r.pare)) 
  
  # save parameters
  x0s[i] <- x0
  thetas[i] <- pareto.theta
  shape1s[i] <- shape1
  shape2s[i] <- shape2
  pBetas[i] <- p.beta
}

parameters.include_1rpUMI <- data.frame(types4, x0s, thetas, shape1s, shape2s, pBetas)
colnames(parameters.include_1rpUMI) <- c('type', 'x0', 'theta', 'shape1', 'shape2', 'pBeta')
r.inc1.ag <- r.ag
r.inc1.ga <- r.ga
r.inc1.ct <- r.ct
r.inc1.tc <- r.tc


##################################################################
# save fit statistics for calculating p-values
##################################################################
bkg.error <- list(parameters.include_1rpUMI = parameters.include_1rpUMI, 
                  parameters.exclude_1rpUMI = parameters.exclude_1rpUMI, 
                  r.exc1.ag = r.exc1.ag, 
                  r.exc1.ga = r.exc1.ga,
                  r.exc1.ct = r.exc1.ct,
                  r.exc1.tc = r.exc1.tc,
                  r.inc1.ag = r.inc1.ag, 
                  r.inc1.ga = r.inc1.ga,
                  r.inc1.ct = r.inc1.ct,
                  r.inc1.tc = r.inc1.tc)

save(bkg.error, file='bkg.error.v2.4.RData')
