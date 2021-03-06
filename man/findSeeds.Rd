% Generated by roxygen2 (4.1.1): do not edit by hand
% Please edit documentation in R/findSeeds.R
\name{findSeeds}
\alias{findSeeds}
\title{To find all seed compounds in the metabolic graph}
\usage{
findSeeds(mbgraph)
}
\arguments{
\item{mbgraph}{igraph object representing the metabolic graph of interest}
}
\description{
Function finds strongly connected components within a bipartite metabolic network.
And selects for components with at least 1 outgoing edge and no inbound edges.
}

