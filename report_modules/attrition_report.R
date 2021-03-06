# Attrition report
# July 17, 2014
# The purpose of this script is to create an FLW attrition report module for the
# data platform. This report will be based on the aggregate FLW monthly tables
# which were computed from the data platform visit tables.
#------------------------------------------------------------------------------#

# Clear workspace and attach packages
# rm(list = ls())
# suppressPackageStartupMessages
library(zoo) #work with mm/yy calendar dates without day
library(ggplot2) #graphing across multiple domains
library(gridExtra) #graphing plots in columns/rows for ggplot
library(RColorBrewer) #Color palettes

render <- function (db, domains_for_run, report_options, tmp_report_pdf_dir) {
  output_directory <- tmp_report_pdf_dir
  
  source(file.path("function_libraries","db_queries.R", fsep = .Platform$file.sep))
  domain_table <- get_domain_table(db)
  
  source(file.path("function_libraries","report_utils.R", fsep = .Platform$file.sep))
  monthly_table <- get_aggregate_table (db, "aggregate_monthly_interactions", domains_for_run)
  all_monthly <- add_splitby_col(monthly_table,domain_table,report_options$split_by)
  #------------------------------------------------------------------------#
  
  #Remove demo users
  #We also need to find a way to exclude admin/unknown users
  all_monthly = all_monthly[!(all_monthly$user_id =="demo_user"),]
  
  #Remove any dates before report start_date and after report end_date
  names (all_monthly)[names(all_monthly) == "first_visit_date.x"] = "first_visit_date"
  all_monthly$first_visit_date = as.Date(all_monthly$first_visit_date)
  all_monthly$last_visit_date = as.Date(all_monthly$last_visit_date)
  start_date = as.Date(report_options$start_date)
  end_date = as.Date(report_options$end_date)
  all_monthly = subset(all_monthly, all_monthly$first_visit_date >= start_date
                       & all_monthly$last_visit_date <= end_date)
  
  #Convert calendar_month (character) to yearmon class since as.Date won't work 
  #without a day.
  all_monthly$month.index = as.yearmon(all_monthly$month.index, "%b %Y")
  
  #Change column names as needed
  names (all_monthly)[names(all_monthly) == "X"] = "row_num"
  names (all_monthly)[names(all_monthly) == "month.index"] = "calendar_month"
  names (all_monthly)[names(all_monthly) == "active_day_percent"] = "active_days_percent"
  names (all_monthly)[names(all_monthly) == "domain"] = "domain_char"
  names (all_monthly)[names(all_monthly) == "numeric_index"] = "obsnum"
  
  #Perform the following function by flw
  #If the flw has been around for only one month
  #That month will always have retained = F and addition = T
  #If the flw has been around for more than one month
  #The last month for each flw will always have retained = F
  #The first month for each flw will always have addition = T 
  #The next t row should always be just one step up from the previous t row (retained = T)
  #If not equal, then the FLW was not retained (retained = F) 
  #The next t row should always be just one step up from the previous t row (addition = F)
  #If not equal, then the flw was added (addition = T) 
  
  retain_add <- function(x) {
    if (length(x$obsnum) == 1) {
      x$retained <- FALSE
      x$addition <- TRUE
    }
    else {
      x$retained <- c(x$obsnum[1:(length(x$obsnum)-1)] + 1 == x$obsnum[2:length(x$obsnum)], FALSE)
      x$addition <- c(TRUE, x$obsnum[2:length(x$obsnum)] != x$obsnum[1:(length(x$obsnum)-1)] + 1)
    }
    return(x)
  }
  
  #Get rid of calendar_month for this part because it is not supported for this
  #operation. We can always add it back later.
  df1 = select(all_monthly, -calendar_month)
  df1 = arrange(df1, user_id, obsnum)
  df_group = group_by(df1, user_id)
  df2 <- retain_add(df_group)
  
  #This gives the attrition rate in the next month, using the # in obsnum as the denominator
  #Numerator is # of flws that are not retained in the next month from the previous month
  #This also gives the addition rate in the obsnum month, using # in obsnum as the denominator
  #Numerator is # of flws that were added in for that obsnum  
  attrition_table = ddply(df2, .(obsnum), 
                          function(x) c(attrition=mean(!x$retained)*100, 
                                        additions=mean(x$addition)*100))
  
  attrition_table_split = ddply(df2, .(obsnum, split_by), 
                                function(x) c(attrition=mean(!x$retained)*100, 
                                              additions=mean(x$addition)*100))
  
  
  #-----------------------------------------------------------------------------#
  
  #CREATE PLOTS
  
  #-----------------------------------------------------------------------------#
  
  #Number of users by obsnum
  #Overall dataset
  #Number of users by monthly index
  all_monthly$count_user = 1
  overall = ddply(all_monthly, .(obsnum), summarise,
                  sum_user = sum(count_user, na.rm=T))
  p_users = ggplot(overall, aes(x=obsnum, y=sum_user)) +
    geom_point(size = 6, shape = 19, alpha = 0.5, colour = "darkblue", 
               fill = "lightblue") +
    geom_line(colour = "darkblue") + 
    scale_size_area() +
    ggtitle("Number of users by monthly index") +
    theme(plot.title = element_text(size=14, face="bold"))
  
  #-----------------------------------------------------------------------------#
  #PRINT PLOTS AND EXPORT TO PDF
  #-----------------------------------------------------------------------------#
  require(gridExtra)
  module_pdfs <- list()
  report_output_dir <- file.path(tmp_report_pdf_dir, "reports")
  dir.create(report_output_dir, showWarnings = FALSE)
  
  outfile <- file.path(report_output_dir,"Number_users_attrition.pdf")
  pdf(outfile)
  grid.arrange(p_users, nrow=1)
  dev.off()
  module_pdfs <- c(module_pdfs,outfile)
  #-----------------------------------------------------------------------------#
  # Attrition and Addition (%) graphs - overall
  
  g_attrition = 
    ggplot(data=attrition_table, aes(x=obsnum, y=attrition)) +
    geom_line(color = "indianred1", size = 1.3) +
    ggtitle("FLWs lost in next month (%) by monthly index") +
    theme(plot.title = element_text(size=14, face="bold")) + 
    xlab("Month index") +
    ylab("Attrition (%)") + 
    theme(axis.text=element_text(size=12), axis.title=element_text(size=14,
                                                                   face="bold"))
  
  g_addition = 
    ggplot(data=attrition_table, aes(x=obsnum, y=additions)) +
    geom_line(color = "darkblue", size = 1.3) +
    ggtitle("FLWs added each month (%) by monthly index") +
    theme(plot.title = element_text(size=14, face="bold")) + 
    xlab("Month index") +
    ylab("Addition (%)") + 
    theme(axis.text=element_text(size=12), axis.title=element_text(size=14,
                                                                   face="bold"))
  
  #-----------------------------------------------------------------------------#
  # Attrition and Addition (%) graphs - split-by
  
  g_attrition_split = 
    ggplot(data=attrition_table_split, aes(x=obsnum, y=attrition)) +
    geom_line(aes(group=split_by, colour=split_by), size=1.3)+
    ggtitle("FLWs lost in next month (%) by monthly index") +
    theme(plot.title = element_text(size=14, face="bold")) + 
    xlab("Month index") +
    ylab("Attrition (%)") + 
    theme(axis.text=element_text(size=12), axis.title=element_text(size=14,
                                                                   face="bold"))
  
  g_addition_split = 
    ggplot(data=attrition_table_split, aes(x=obsnum, y=additions)) +
    geom_line(aes(group=split_by, colour=split_by), size=1.3) +
    ggtitle("FLWs added each month (%) by monthly index") +
    theme(plot.title = element_text(size=14, face="bold")) + 
    xlab("Month index") +
    ylab("Addition (%)") + 
    theme(axis.text=element_text(size=12), axis.title=element_text(size=14,
                                                                   face="bold"))
  
  #g_attrition_addition = 
  # ggplot(data=attrition_table, aes(x=obsnum)) + 
  #geom_line(aes(y = attrition, colour = "darkblue"), size = 1.25) + 
  #geom_line(aes(y = additions, colour = "indianred1"), size = 1.25)
  
  #-----------------------------------------------------------------------------#
  #PRINT PLOTS AND EXPORT TO PDF
  #-----------------------------------------------------------------------------#
  
  outfile <- file.path(report_output_dir,"Attrition.pdf")
  pdf(outfile)
  grid.arrange(g_attrition, g_attrition_split, nrow=2)
  dev.off()
  module_pdfs <- c(module_pdfs,outfile)
  
  outfile <- file.path(report_output_dir,"Addition.pdf")
  pdf(outfile)
  grid.arrange(g_addition, g_addition_split, nrow=2)
  dev.off()
  module_pdfs <- c(module_pdfs,outfile)
  
  return(module_pdfs)
}

