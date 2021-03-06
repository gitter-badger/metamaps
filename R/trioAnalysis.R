#' findTrios searches valid three-KO reactions resticting by the center KO and reports reaction clusters
#'
#'
#' findTrios uses K-means clustering to identify reaction groups/clusters and the GAP statistic by Ryan Tibshirani to identity the best k implemented in the library cluster
#' Clustering algorithm uses the input matrix cmoposed of the the KS statistics of the KOs flanking the KO of interest. 
#'
#' The KS statistics is calculated based on the comparison of each KO's gene/contig expression distribution against the 'null' ie. 
#' empirical distribution against all genes in all contigs
#'
#' In addition it also identifies reactions where flanking KOs have high gene diversity, given by low KS (<= 0.5)
#'
#'
#' @param KOI KOs-of-interest ie KOs above a selected amount of expression ie. highly expressed KOs and with D-statistics above that of the desired threshold
#' @param ks  Precalculated data.frame output from ksCal fxn containing all KO's gene distribution  KS statistic when compared with whole sample's empirical gene distribution
#' @param toPrint conditional to print the results of the classification plots
#'
#' @return data.frame of all reactions, corresponding clusters and the KS statistics for each KO and the selected Cluster
#'
#' @export
findTrios <- function(KOI, ks, toPrint = TRUE){
    lapply(KOI, function(midKO){
        trioDF = trio(midKO) %>% mutate(rxnNum = 1:n())
        if(is.na(trioDF)){
               message(sprintf("%s is not a metabolic KO", midKO))
            data.frame(
                    rxnNum = integer(),
                    before.x = numeric(), 
                    middle.x = numeric(), 
                    after.x = numeric(), 
                    cluster = integer(), 
                    before.y = character(),
                    middle.y = character(),
                    after.y = character(),
                    selected = integer()
                       )
        }else{
            lineLong = trioDF %>% tidyr::gather(rxntype, ko, -rxnNum) %>% merge(ks, all.x   = T)
            #removes rxns where the KOs have no expression
            NArxns = lineLong[lineLong %>% apply(1, function(x) is.na(x) %>% sum ) > 0 ,]$rxnNum
            lineLong = filter(lineLong, !rxnNum %in% NArxns)
            
            #input matrix of KS values of the before and after KOs for to cluster the reactions.
            m        =  lineLong                                 %>%
                        dplyr::select(rxnNum, rxntype, d)       %>%
                        tidyr::spread(key = rxntype, value = d)
            clusteredM = findK(m)

            if(toPrint) clusteredM %$% plotClassification(matrix, ko = midKO) %>% print

            within.ksDF <-   1:clusteredM$k %>% lapply(function(cl){
                clusteredM %$% 
                    filter(matrix, cluster == cl) %$%
                    data.frame(
                       k     = cl,
                       value = ks.test(before, after, alternative = "two.sided") %$% statistic,
                       before.median =  median(before),
                       after.median   = median(after)
                       )
            })  %>%
            do.call(rbind,.) %>% arrange(k)

            #arbitary threshold
            selectedCluster = filter(within.ksDF, before.median <= 0.5, after.median <= 0.5, value == min(value))

            if(nrow(selectedCluster) > 1 | nrow(selectedCluster) == 0){
                sprintf("%s groupFilter: %s", midKO, nrow(selectedCluster)) %>% message
                finalM = clusteredM$matrix %>% merge(trioDF, by="rxnNum")
                finalM$selected = data.frame(
                    rxnNum = integer(),
                    before.x = numeric(), 
                    middle.x = numeric(), 
                    after.x = numeric(), 
                    cluster = integer(), 
                    before.y = character(),
                    middle.y = character(),
                    after.y = character(),
                    selected = integer()
                       )

            }else{
                finalM = clusteredM$matrix %>% merge(trioDF, by="rxnNum")
                finalM$selected = selectedCluster$k
        }
    }
})
}

#''findK to find the optimum number of Ks
#'
#' using cluster::clusGap
#'
#' @param theMatrix    two column data.frame with KS values of the before and after KOs in the reactions
#' @param kmax         the max number of Ks to test for; defaults to 10
#'
#' @return optimum number of Ks to choose
findK <- function(theMatrix, kmax = 10){
        clusTab = theMatrix %>% dplyr::select(before, after) %>%
                    cluster::clusGap(kmeans, B=100, K.max=kmax, iter.max=1000,nstart=100) %$%
                    Tab %>% as.data.frame

        winning = clusTab %$% gap[gap[-kmax] > (gap[-1] - SE.sim[-1])] %>% min
        optiK = which(clusTab$gap == winning)
        theMatrix$cluster = theMatrix %>% select(before, after) %>% 
        kmeans(centers = optiK, iter.max=1000,nstart=100) %$% cluster
        list(k = optiK, matrix = theMatrix)
}


#' Plot clustering
#'
#' @param matrix    input matrix for plotting needs before and after column
#' @param ko        the koID for printing the KO name and ID to the diagnostic plot
plotClassification = function(matrix, ko){
    matrix                               %>% 
    select(-middle, -rxnNum) %>%
    tidyr::gather(rxntype, ks, -cluster) %>%
        ggplot(aes(ks))                                 +
        geom_density(aes(group=rxntype, color=rxntype)) +
        facet_wrap(~cluster) + 
        ggtitle(sprintf("%s - %s",ko, koname(ko)$ko.definition))
}

#' ksCal generates KS statistics for aKO given the base distribution
#'
#' runs a "two.sided" KS test and reports the KS and p value
#'
#'
#' @param contigDF          data.frame with count frequency and rpkm of ALL KOs' contigs for both gDNA and cDNA obtained from query
#' @param baseDistribution  the 
#' @param cores             number of cores to use
#'
#' @return data.frame with columns: ko, p.value and KS statistic (D)
#'
#' @export
ksCal <- function(contigDF, baseDistribution, cores){

    group1 = baseDistribution$rpkm_cDNA %>% as.numeric

    contigDF %$%
    ko       %>%
    unique   %>%
    mclapply(
         function(koid){
             group2  =  filter(contigDF, ko == koid)$rpkm_cDNA %>% as.numeric
             ks      =  ks.test(group1, group2, alternative="two.sided")
             data.frame(ko   =  koid,
                    p.value  =  ks$p.value,
                    d        =  ks$statistic)
    },mc.cores = cores) %>%
    do.call(rbind,.)
}

#' returns gene/contig infomation for all KOs
#'
#' queries graphDB and extracts information for all genes in all KOs, outputs this into a data.frame
#'
#' @return returns data.frame with columns: contigName, Freq_cDNA, rpkm_cDNA, Freq_gDNA, rpkm_gDNA, ko
#'
#' @export
getContigs <- function(){
    query="
    MATCH
        (c:contigs)
    RETURN
        c.contig as contigName,
        c.cDNAFreq AS Freq_cDNA,
        c.cDNAFPKM as rpkm_cDNA,
        c.gDNAFreq as Freq_gDNA,
        c.gDNAFPKM as rpkm_gDNA
    "
    dbquery(query) %>% make.data.frame
}
