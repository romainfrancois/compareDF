
#' @title Compare Two dataframes
#'
#' @description Do a git style comparison between two data frames of similar columnar structure
#'
#' @param df_new The data frame for which any changes will be shown as an addition (green)
#' @param df_old The data frame for which any changes will be shown as a removal (red)
#' @param group_col A character vector of a string of character vector showing the columns
#'  by which to group_by.
#' @param exclude The columns which should be excluded from the comparison
#' @param limit_html maximum number of rows to show in the html diff. >1000 not recommended
#' @param stop_on_error Whether to stop on acceptable errors on not
#' @param tolerance The amount in fraction to which changes are ignored while showing the
#'  visual representation. By default, the value is 0 and any change in the value of variables
#'  is shown off. Doesn't apply to categorical variables.
#' @param tolerance_type Defaults to 'ratio'. The type of comparison for numeric values, can be 'ratio' or 'difference'
#' @param keep_unchanged whether to preserve unchanged values or not. Defaults to \code{FALSE}
#' @param color_scheme What color scheme to use for the HTML output. Should be a vector/list with
#'  named_elements. Default - \code{c("addition" = "green", "removal" = "red", "unchanged_cell" = "gray", "unchanged_row" = "deepskyblue")}
#' @param html_headers A character vector of column names to be used in the table. Defaults to \code{colnames}.
#' @param html_change_col_name Name of the change column to use in the HTML table. Defaults to \code{chng_type}.
#' @param html_group_col_name Name of the group column to be used in the table (if there are multiple grouping vars). Defaults to \code{grp}.
#' @import dplyr
#' @export
#' @examples
#' old_df = data.frame(var1 = c("A", "B", "C"),
#'                     val1 = c(1, 2, 3))
#' new_df = data.frame(var1 = c("A", "B", "C"),
#'                     val1 = c(1, 2, 4))
#' ctable = compare_df(new_df, old_df, c("var1"))
#' print(ctable$comparison_df)
#' ctable$html_output
compare_df <- function(df_new, df_old, group_col, exclude = NULL, limit_html = 100, tolerance = 0, tolerance_type = 'ratio',
                       stop_on_error = TRUE, keep_unchanged = FALSE,
                       color_scheme = c("addition" = "green", "removal" = "red", "unchanged_cell" = "gray", "unchanged_row" = "deepskyblue"),
                       html_headers = NULL, html_change_col_name = "chng_type", html_group_col_name = "grp"){

  both_tables = list(df_new = df_new, df_old = df_old)
  if(!is.null(exclude)) both_tables = exclude_columns(both_tables, exclude)

  check_if_comparable(both_tables$df_new, both_tables$df_old, group_col, stop_on_error)
  both_tables$df_new = both_tables$df_new[, names(both_tables$df_old)]

  if (length(group_col) > 1) {
    both_tables = group_columns(both_tables, group_col)
    group_col = "grp"
  }

  both_diffs = combined_rowdiffs(both_tables)

  check_if_similar_after_unique_and_reorder(both_tables, both_diffs, stop_on_error)

  comparison_table         = create_comparison_table(both_diffs, group_col)

  comparison_table_ts2char = .ts2char(comparison_table)
  comparison_table_diff    = create_comparison_table_diff(comparison_table_ts2char, group_col, tolerance, tolerance_type)

  comparison_table         = eliminate_tolerant_rows(comparison_table, comparison_table_diff)
  comparison_table_ts2char = comparison_table_ts2char %>% eliminate_tolerant_rows(comparison_table_diff)
  comparison_table_diff    = eliminate_tolerant_rows(comparison_table_diff, comparison_table_diff)

  if(keep_unchanged) {

    comparison_table = comparison_table %>% keep_unchanged_rows(both_tables, group_col, "val_table")
    comparison_table_ts2char = comparison_table_ts2char %>% keep_unchanged_rows(both_tables, group_col, "val_table")
    comparison_table_diff    = comparison_table_diff %>% keep_unchanged_rows(both_tables, group_col, "color_table")

    comparison_table_diff = comparison_table_diff[order(comparison_table[[group_col]]),]
    comparison_table_ts2char = comparison_table_ts2char[order(comparison_table[[group_col]]),]
    comparison_table = comparison_table[order(comparison_table[[group_col]]),]
  }

  if(nrow(comparison_table) == 0) stop_or_warn("The two data frames are the same after accounting for tolerance!", stop_on_error)
  if(nrow(comparison_table_diff) == 0) stop_or_warn("The two data frames are the same after accounting for tolerance!", stop_on_error)

  html_headers_all = get_headers_for_html_table(html_headers, html_change_col_name, html_group_col_name, comparison_table_diff)

  if (limit_html > 0 & nrow(comparison_table_diff) > 0 & nrow(comparison_table) > 0)
    html_table = create_html_table(comparison_table_diff, comparison_table_ts2char, group_col, limit_html, color_scheme, html_headers_all) else
      html_table = NULL
  change_count =  create_change_count(comparison_table, group_col)
  change_summary =  create_change_summary(change_count, both_tables)

  comparison_table$chng_type = comparison_table$chng_type %>% replace_numbers_with_symbols()
  comparison_table_diff = comparison_table_diff %>% replace_numbers_with_symbols()

  list(comparison_df = comparison_table, html_output = html_table,
       comparison_table_diff = comparison_table_diff,
       change_count = change_count, change_summary = change_summary)

}

keep_unchanged_rows <- function(comparison_table, both_tables, group_col, type){
  unchanged_rows = lapply(both_tables, function(x) x[!(x[[group_col]] %in% comparison_table[[group_col]]), ] ) %>%
    Reduce(rbind, .) %>% dplyr::mutate(chng_type = '0')

  if(type == 'color_table') unchanged_rows[] = -1
  comparison_table %>% rbind(unchanged_rows)
}

replace_numbers_with_symbols <- function(x){
  if(is.vector(x) && length(x) == 0) return(x)
  if(is.data.frame(x) && nrow(x) == 0) return(x)
  x[x == 2] = "+"
  x[x == 1] = "-"
  x[x == 0] = "="
  x[x == -1] = "="
  x
}

exclude_columns <- function(both_tables, exclude){
  list(df_old = both_tables$df_old %>% select(-one_of(exclude)),
       df_new = both_tables$df_new %>% select(-one_of(exclude)))
}

group_columns <- function(both_tables, group_col){
  message("Grouping grouping columns")
  df_combined = rbind(both_tables$df_new %>% mutate(from = "new"), both_tables$df_old %>% mutate(from = "old"))
  df_combined = df_combined %>% piped.do.call(group_by_, group_col) %>% data.frame(grp = group_indices(.), .) %>% ungroup
  list(df_new = df_combined %>% filter(from == "new") %>% select(-from),
       df_old = df_combined %>% filter(from == "old") %>% select(-from))
}

combined_rowdiffs <- function(both_tables){
  list(df1_2 = rowdiff(both_tables$df_old, both_tables$df_new),
       df2_1 = rowdiff(both_tables$df_new, both_tables$df_old))
}

stop_or_warn <- function(text, stop_on_error = TRUE){
  if(stop_on_error) stop(text) else warning(text)
}

check_if_similar_after_unique_and_reorder <- function(both_tables, both_diffs, stop_on_error){
  if(any(sapply(both_diffs, nrow) != 0)) return(TRUE)
  if(nrow(both_tables$df_new) == nrow(both_tables$df_old))
    stop_or_warn("The two dataframes are similar after reordering", stop_on_error) else
      stop_or_warn("The two dataframes are similar after reordering and doing unique", stop_on_error)

}

create_comparison_table <- function(both_diffs, group_col){
  message("Creating comparison table...")
  mixed_df = both_diffs$df1_2 %>% mutate(chng_type = NA_integer_) %>% slice(0) %>% data.frame()
  if(nrow(both_diffs$df1_2) != 0) mixed_df = mixed_df %>% rbind(data.frame(chng_type = "1", both_diffs$df1_2))
  if(nrow(both_diffs$df2_1) != 0) mixed_df = mixed_df %>% rbind(data.frame(chng_type = "2", both_diffs$df2_1))
  mixed_df %>%
    arrange(desc(chng_type)) %>% arrange_(group_col) %>%
    # mutate(chng_type = ifelse(chng_type == 1, "1", "2")) %>%
    select(one_of(group_col), everything()) %>% r2two()
}


create_comparison_table_diff <- function(comparison_table_ts2char, group_col, tolerance, tolerance_type){
  comparison_table_ts2char %>% group_by_(group_col) %>%
    do(.diff_type_df(., tolerance = tolerance, tolerance_type = tolerance_type)) %>% as.data.frame
}

eliminate_tolerant_rows <- function(comparison_table, comparison_table_diff){
  rows_inside_tolerance = comparison_table_diff %>% select(-chng_type) %>%
    apply(1, function(x) all(x == 0))
  comparison_table %>% filter(!rows_inside_tolerance)
}

#' @importFrom utils head
create_html_table <- function(comparison_table_diff, comparison_table_ts2char, group_col, limit_html, color_scheme, html_headers_all){

  comparison_table_ts2char$chng_type = comparison_table_ts2char$chng_type %>% replace_numbers_with_symbols()

  if(limit_html > 1000 & comparison_table_diff %>% nrow > 1000)
    warning("Creating HTML diff for a large dataset (>1000 rows) could take a long time!")

  if(limit_html < nrow(comparison_table_diff))
    message("Truncating HTML diff table to ", limit_html, " rows...")

  requireNamespace("htmlTable")
  comparison_table_color_code  = comparison_table_diff %>% do(.colour_coding_df(., color_scheme)) %>% as.data.frame

  shading = ifelse(sequence_order_vector(comparison_table_ts2char[[group_col]]) %% 2, "#dedede", "white")

  table_css = lapply(comparison_table_color_code, function(x)
    paste0("padding: .2em; color: ", x, ";")) %>% data.frame %>% head(limit_html) %>% as.matrix()

  colnames(comparison_table_ts2char) <- html_headers_all

  message("Creating HTML table for first ", limit_html, " rows")
  html_table = htmlTable::htmlTable(comparison_table_ts2char %>% head(limit_html),
                                    col.rgroup = shading,
                                    rnames = F, css.cell = table_css,
                                    padding.rgroup = rep("5em", length(shading))
  )
}

check_if_comparable <- function(df_new, df_old, group_col, stop_on_error){

  if(isTRUE(all.equal(df_old, df_new))) stop_or_warn("The two data frames are the same!", stop_on_error)

  if(!(all(names(df_new) %in% names(df_old)))) stop("The two data frames have different columns!")

  if(any(c("chng_type", "X2", "X1") %in% group_col)) stop("chng_type, X1, X2) are reserved keywords!")

  if(!all(group_col %in% names(df_new))) stop("Grouping column(s) not found in the data.frames!")

  return(TRUE)

}

r2two <- function(df, round_digits = 2)
{
  numeric_cols = which(sapply(df, is.numeric))
  df[, numeric_cols] = lapply(df[, numeric_cols, drop = F], round, round_digits)

  df
}

.colour_coding_df <- function(df, color_scheme){
  if(nrow(df) == 0) return(df)
  df[df == 2] = color_scheme[['addition']]
  df[df == 1] = color_scheme[['removal']]
  df[df == 0] = color_scheme[['unchanged_cell']]
  df[df == -1] = color_scheme[['unchanged_row']]
  df
}

#' @importFrom stats na.omit
.diff_type_df <- function(df, tolerance = 1e-6, tolerance_type = 'ratio'){

  lapply(df, function(x) {
    len_unique_x = length(na.omit(unique(x)))

    # Score = 1 here implies it should be coloured
    if(length(na.omit(x)) == 1){
      score = 1
    }else{
      if(is.numeric(x) & !is.POSIXct(x) & len_unique_x > 1){

        range_x = diff(range(x, na.rm = T))
        if(tolerance_type == 'ratio') score = as.numeric(abs(range_x/min(x, na.rm = T)) > tolerance) else
          if(tolerance_type == 'difference') score = range_x > tolerance else
            stop("Unknown tolerance type: Should be `ratio` or `difference`")

      }else
        score = as.numeric(len_unique_x > 1)
    }
    # This step decides what colour it should be.
    score = score + score * as.numeric(df$chng_type == "2")
  }) %>% data.frame
}

# Courtesy - Gabor Grothendieck
# rowdiff2 <- function(x.1,x.2,...){
#   do.call("rbind", setdiff(split(x.1, rownames(x.1)), split(x.2, rownames(x.2))))
# }

rowdiff <- function(x.1,x.2,...){
  if(nrow(x.2) == 0) return(x.1)
  x.1[!duplicated(rbind(x.2, x.1))[-(1:nrow(x.2))],]
}

.ts2char <- function(df)
{
  ts_cols = which(sapply(df, is.POSIXct))
  if (length(ts_cols) != 1) {
    df[, ts_cols] = lapply(df[, ts_cols], as.character)
  }else
    df[[ts_cols]] = as.character(df[[ts_cols]])

    df
}

piped.do.call = function(x, fname, largs) do.call(fname, c(list(x), largs))

is.POSIXct <- function(x) inherits(x, "POSIXct")

sequence_order_vector <- function(data)
{
  temp1 <- rle(as.vector(data))$lengths
  rep(seq_along(temp1),temp1) - 1L
}

create_change_count <- function(comparison_table_ts2char, group_col){
  change_count = comparison_table_ts2char %>% group_by_(group_col, "chng_type") %>% tally()
  change_count_replace = change_count %>% tidyr::spread(key = chng_type, value = n) %>% data.frame
  change_count_replace[is.na(change_count_replace)] = 0

  if(is.null(change_count_replace[['X1']])) change_count_replace = change_count_replace %>% mutate(X1 = 0L)
  if(is.null(change_count_replace[['X2']])) change_count_replace = change_count_replace %>% mutate(X2 = 0L)
  change_count_replace = change_count_replace %>% as.data.frame %>%
    tidyr::gather_("variable", "value", c("X2", "X1"))

  change_count = change_count_replace %>% group_by_(group_col) %>% arrange_('variable') %>%
    summarize(changes = min(value), additions = value[2] - value[1], removals = value[1] - value[2]) %>%
    mutate(additions = replace(additions, is.na(additions) | additions < 0, 0)) %>%
    mutate(removals = replace(removals, is.na(removals) | removals < 0, 0))

  change_count

}

create_change_summary <- function(change_count, both_tables){
  c(old_obs = nrow(both_tables$df_old), new_obs = nrow(both_tables$df_new),
    changes = sum(change_count$changes), additions = sum(change_count$additions), removals = sum(change_count$removals))
}

get_headers_for_html_table <- function(headers, change_col_name, group_col_name, comparison_table_diff) {
  # if (is.null(headers)) return(names(comparison_table_diff))

  headers_all = names(comparison_table_diff) %>%
    replace(. == 'grp', group_col_name) %>%
    replace(. == 'chng_type', change_col_name)

  matching_vals = names(headers) %>% sapply(function(x) which(x == headers_all)) %>% Filter(function(x) length(x) > 0, .) %>% unlist()
  headers_all[matching_vals] = headers[names(matching_vals)]

  headers_all
}

# nocov start
#' @title View Comparison output HTML
#'
#' @description Some versions of Rstudio doesn't automatically show the html pane for the html output. This is a workaround
#'
#' @param comparison_output output from the comparisonDF compare function
#' @export
#' @examples
#' old_df = data.frame(var1 = c("A", "B", "C"),
#'                     val1 = c(1, 2, 3))
#' new_df = data.frame(var1 = c("A", "B", "C"),
#'                     val1 = c(1, 2, 4))
#' ctable = compare_df(new_df, old_df, c("var1"))
#' # Not Run::
#' # view_html(ctable)
view_html <- function(comparison_output){
  temp_dir = tempdir()
  temp_file <- paste0(temp_dir, "/temp.html")
  cat(comparison_output$html_output, file = temp_file)
  getOption("viewer")(temp_file)
  unlink("temp.html")
}
# nocov end

# Deprecated. Will bring it back in a letter version if deemed necessary
# create_change_detail_summary <- function(){
#   change_detail = comparison_table_diff
#   change_detail[[group_col]] = comparison_table_ts2char[[group_col]]
#   change_detail = change_detail %>% reshape::melt.data.frame(group_col)
#
#   change_detail_replace = change_detail %>% group_by_(group_col, "variable", "value") %>% tally()
#   change_detail_replace = change_detail_replace %>% group_by_(group_col, "variable") %>% tidyr::spread(key = value, value = n)
#   change_detail_replace[is.na(change_detail_replace)] = 0
#   change_detail_summary_replace = change_detail_replace %>% data.frame %>% dplyr::rename(param = variable) %>%
#     mutate(param = as.character(param)) %>% tidyr::gather("variable", "value", 3:ncol(.))
#
#   change_detail_count = change_detail_summary_replace %>% group_by_(group_col, "param") %>% arrange(desc(variable)) %>%
#     summarize(changes = min(value[1:2]), additions = value[1] - value[2], removals = value[2] - value[1]) %>%
#     mutate(additions = replace(additions, is.na(additions), 0)) %>%
#     mutate(removals = replace(removals, is.na(removals), 0))
#   change_detail_count = change_detail_count %>%
#     mutate(replace(changes, changes < 0, 0)) %>%
#     mutate(replace(removals, removals < 0, 0)) %>%
#     mutate(replace(additions, additions < 0, 0))
#
#   change_detail_count_summary = change_detail_count %>% group_by(param) %>%
#     summarize(total_changes = sum(changes), total_additions = sum(additions), tot_removals = sum(removals))
# }
