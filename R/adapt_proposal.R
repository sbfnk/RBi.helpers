#' @rdname adapt_proposal
#' @name adapt_proposal
#' @title Adapt the proposal distribution of MCMC using the covariance
#'   of samples
#' @description This function takes the provided \code{\link{libbi}} object and
#'   runs MCMC, adapting the proposal distribution until the desired
#'   acceptance rate is achieved. If a scale is given, it will be used
#'   to adapt the proposal at each iteration
#' @param wrapper \code{link{libbi}} (which has been run) to study
#' @param min minimum acceptance rate
#' @param max maximum acceptance rate
#' @param scale scale multiplier/divider for the proposal. If >1 this
#'   will be inverted.
#' @param options list of additional options
#' @param nsamples number of samples to generate each iteration
#' @param max_iter maximum of iterations (default: 10)
#' @param correlations if TRUE (default), take into account correlations
#' @param quiet if set to TRUE, will not provide running output of particle numbers tested
#' @param ... parameters for \code{\link{sample}}
#' @return a \code{\link{libbi}} with the desired proposal distribution
#' @importFrom coda mcmc rejectionRate
#' @importFrom rbi bi_dim_len get_traces
#' @examples
#' example_obs <- bi_read(system.file(package="rbi", "example_output.nc"))
#' example_model <- bi_model(system.file(package="rbi", "PZ.bi"))
#' example_bi <- libbi(model = example_model, obs = example_obs)
#' obs_states <- var_names(example_model, "obs")
#' max_time <- max(sapply(example_obs[obs_states], function(x) { max(x[["time"]])}))
#' # adapt to acceptance rate between 0.1 and 0.5
#' \dontrun{adapted <- adapt_proposal(example_bi, nsamples = 100, end_time = max_time,
#'                                min = 0.1, max = 0.5, nparticles = 256, correlations = TRUE)}
#' @export
adapt_proposal <- function(wrapper, min = 0, max = 1, scale = 2, options, nsamples, max_iter = 10, correlations = TRUE, quiet = FALSE, ...) {

  if (min == 0 && max == 1) return(wrapper)

  if (!(max>min)) stop("Must have max>min.")

  if (missing(options)) {
    options <- list()
  } else if (!is.list(options)) {
    stop("'options' must be given as list.")
  }

  if (!quiet) message(date(), " Adapting the proposal distribution")

  if (!wrapper$run_flag) {
    if (!quiet) message(date(), " Initial trial run")
    rbi::sample(wrapper, ...)
  }

  ## scale should be > 1 (it's a divider if acceptance rate is too
  ## small, multiplier if the acceptance Rate is too big)
  if (scale < 1) scale <- 1 / scale

  if (missing(nsamples)) {
    if ("nsamples" %in% names(wrapper$options)) {
      nsamples <- wrapper$options[["nsamples"]]
    } else {
      stop("must provide 'nsamples'")
    }
  } else {
    options[["nsamples"]] <- nsamples
  }
  accRate <- acceptance_rate(wrapper)
  adapt_wrapper <- wrapper
  shape_adapted <- FALSE
  for (round in seq_len(1 + correlations)) {
    iter <- 1
    adapt_scale <- 1
    while ((round == 2 && !shape_adapted) ||
           (min(accRate) < min || max(accRate) > max || !is.finite(accRate)) &&
           iter <= max_iter) {
      if (is.finite(accRate)) {
        if (!quiet) {
          message(date(), " Acceptance rate ", min(accRate),
                  ", adapting ", ifelse(round == 1, "size", "shape"),
                  " with scale ", adapt_scale)
        }
      }
      adapt_wrapper$model <-
        output_to_proposal(adapt_wrapper, adapt_scale,
                           correlations = (round == 2))
      adapt_wrapper <- rbi::sample(adapt_wrapper,
                                   init=adapt_wrapper,
                                   options = options, chain_init=TRUE, ...)
      mcmc_obj <- coda::mcmc(rbi::get_traces(adapt_wrapper))
      accRate <- max(1 - coda::rejectionRate(mcmc_obj))
      iter <- iter + 1
      if (min(accRate) < min) {
        adapt_scale <- adapt_scale / scale
      } else {
        adapt_scale <- adapt_scale * scale
      }
      if (round == 2) shape_adapted <- TRUE
     }
  }

  if (!quiet) message(date(), " Acceptance rate: ", min(accRate))

  if (iter > max_iter) {
    warning("Maximum of iterations reached")
  }

  return(adapt_wrapper)
}