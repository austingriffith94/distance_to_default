/*Austin Griffith
/*10/31/2017
/*Computing Distance to Default Method 3 (Iterative) for 1970 to 2015
/*Comparison with Method 1 (Naive) and Method 2 (Direct)*/

OPTIONS ls = 70 nodate nocenter;
OPTIONS missing = '';

/*file paths need to be updated according to current computer*/
%let Ppath = P:\Distance to Default;
%let Cpath = Q:\Data-ReadOnly\COMP;
%let Dpath = Q:\Data-ReadOnly\CRSP;

libname comp "&Cpath";
libname crsp "&Dpath";

title 'DD and PD Method 3';

/*---------------------------------------------------Funda---------------------------------------------------*/
/*data is on a yearly basis*/
/*pulls data from funda file*/
data funda;
set comp.funda (keep = indfmt datafmt popsrc fic consol datadate
GVKEY CUSIP DLC DLTT);
where indfmt = 'INDL' and datafmt = 'STD' and popsrc = 'D' and fic = 'USA'
and consol = 'C';
CUSIP = substr(CUSIP,1,8);
YEAR = year(DATADATE);
if YEAR >= 1970 and YEAR <= 2015;
YEAR = YEAR + 1; /*lags data for merging purposes with dsf*/
/*want debt to be greater than zero, else there's an error*/
if DLC > 0;
DLC = DLC*1000000;
if DLTT > 0;
DLTT = DLTT*1000000;
F = DLC + 0.5*DLTT; /*face value of firm debt*/
keep indfmt datafmt popsrc fic consol GVKEY CUSIP DLC DLTT YEAR F;
run;

/*---------------------------------------------------DSF---------------------------------------------------*/
/*data is initially on a daily basis*/
/*pulls data from dsf file*/
data dsf;
set crsp.dsf (keep = CUSIP DATE PRC SHROUT RET);
SHROUT = SHROUT*1000;
YEAR = year(DATE);
format DATE mmddyy10.;
if YEAR >= 1970 and YEAR <= 2015;
E = ABS(PRC)*SHROUT; /*equity value*/
run;

/*computes cumulative annual return and std deviation for each firm*/
/*assume 250 business days a year*/
proc sql NOPRINT;
create table dsf_sql as
select CUSIP, DATE, E as DE, mean(E) as E, /*avg E gets average equity per firm per year*/
exp(sum(log(1+RET)))-1 as ANNRET,
std(RET)*sqrt(250) as SIGMAE,
YEAR + 1 as YEAR
from dsf
group by CUSIP, YEAR;
quit;

/*---------------------------------------------------Merge Funda and DSF---------------------------------------------------*/
/*doesn't remove duplicates for method 3*/
proc sort data = dsf_sql;
by CUSIP YEAR;
run;

/*sorts funda for merging data sets*/
proc sort data = funda;
by CUSIP YEAR;
run;

/*merges funda and dsf data for method 3*/
data funda_dsf_3;
merge funda(in = a) dsf_sql(in = b);
by CUSIP YEAR;
if a & b;
run;

/*sorts dsf for merging data sets*/
/*gets first value per year, removes duplicate years*/
/*collapses daily -----> annual*/
proc sort data = dsf_sql nodupkey;
by CUSIP YEAR;
run;

/*merges funda and dsf data for method 1 and 2*/
data funda_dsf_12;
merge funda(in = a) dsf_sql(in = b);
by CUSIP YEAR;
if a & b;
run;

/*---------------------------------------------------Daily Fed Data---------------------------------------------------*/
/*imports the csv data from the daily fed in my P drive*/
/*used to get risk free interest rates*/
/*removes missing data so that start of year values aren't empty*/
proc import out = dailyfed datafile = "&Ppath\DAILYFED.csv"
dbms = csv
replace;
run;

/*gets interest rates from available data*/
data dailyfed;
set dailyfed;
if nmiss(of DTB3) then delete;
R = DTB3;
RF = log(1 + R/100);
format DATE mmddyy10.;
YEAR = year(DATE);
if 1970 <= YEAR <= 2015;
keep R YEAR RF DATE;
run;

/*---------------------------------------------------Merging Dailyfed and Funda_DSF---------------------------------------------------*/
/*sorts by year for day, done before year to prevent duplicate deletion*/
proc sort data = dailyfed;
by DATE;
run;

/*sorts funda/dsf merge by day*/
proc sort data = funda_dsf_3;
by DATE;
run;

/*creates combined data set that will be used to determine DD and PD in method 3*/
data merge_day;
merge funda_dsf_3(in = a) dailyfed(in = b);
by DATE;
YEAR = YEAR + 1;
if a & b;
run;

/*sorts fed by year for merge*/
/*removes duplicates to get first interest rate at beginning of year*/
/*collapses daily -----> annual*/
proc sort data = dailyfed nodupkey;
by YEAR;
run;

/*sorts funda/dsf merge by year*/
proc sort data = funda_dsf_12;
by YEAR;
run;

/*creates combined data set that will be used to determine DD and PD in method 1 and 2*/
data merge_year;
merge funda_dsf_12(in = a) dailyfed(in = b);
by YEAR;
if a & b;
run;

/*---------------------------------------------------Recession Data---------------------------------------------------*/
/*imports the csv data from USREC*/
proc import out = rec datafile = "&Ppath\USREC.csv"
dbms = csv
replace;
run;

data rec;
set rec;
YEAR = year(DATE);
if 1970 <= YEAR <= 2015;
keep YEAR USREC;
run;

proc sort data = rec;
by YEAR;
run;

/*---------------------------------------------------Baa Fed Fund Spread---------------------------------------------------*/
/*imports the data from BAAFFM csv file*/
/*file already in a annualized format, so just format for merge*/
proc import out = baa datafile = "&Ppath\BAAFFM.csv"
dbms = csv
replace;
run;

data baa;
set baa;
YEAR = year(DATE);
if 1970 <= YEAR <= 2015;
keep YEAR BAAFFM;
run;

proc sort data = baa;
by YEAR;
run;

/*---------------------------------------------------Cleveland Stress Index---------------------------------------------------*/
/*imports the data from the CFSI csv file*/
/*also annualized, but only goes from 1992 to 2016, so graph accordingly*/
proc import out = stress datafile = "&Ppath\CFSI.csv"
dbms = csv
replace;
run;

data stress;
set stress;
YEAR = year(DATE);
if 1970 <= YEAR <= 2015;
keep YEAR CFSI;
run;

proc sort data = stress;
by YEAR;
run;

/*---------------------------------------------------Method 1 and 2---------------------------------------------------*/
/*initializes V and sigmaV values for method 2*/
data merge_year;
set merge_year;
V2 = E + F;
SIGMAV2 = (E/(E+F))*SIGMAE + (F/(E+F))*SIGMAE*0.25;
if nmiss(of E) then delete;
if nmiss(of F) then delete;
if nmiss(of SIGMAE) then delete;
run;

/*sorts by cusip and year for proc model*/
proc sort data = merge_year;
by CUSIP YEAR;
run;

/*using proc model, calculate V and sigma V by solving for the two equations below*/
/*uses the newton method to simulate until V and sigmaV change by less than 1e-3*/
proc model data = merge_year noprint converge = 0.001 newton;
eq.equity = V2*CDF('normal',(log(V2/F)+ RF + SIGMAV2*SIGMAV2*0.5)/SIGMAV2) - exp(-1*RF)*F*CDF('normal',(log(V2/F) + RF + SIGMAV2*SIGMAV2*0.5)/SIGMAV2 - SIGMAV2) - E;
eq.sig_e = (V2/E)*CDF('normal',(log(V2/F)+ RF + SIGMAV2*SIGMAV2*0.5)/SIGMAV2)*SIGMAV2 - SIGMAE;
solve V2 SIGMAV2 / out = solve2;
by CUSIP YEAR;
id F ANNRET;
quit;

/*gets DD and PD values from modeled V and sigmav*/
/*solves for DD and PD with naive method*/
data data_method12;
set solve2;
/*method 2 calculations*/
DD_direct = (log(V2/F) + (ANNRET - SIGMAV2*SIGMAV2*0.5))/SIGMAV2;
PD_direct = CDF('normal',-DD_direct);
if nmiss(of DD_direct) then delete;
/*method 1 calculations*/
SIGMAD = 0.05 + .025*SIGMAE;
SIGMAV1 = (E*SIGMAE)/(E+F) + (F*SIGMAD)/(E+F);
DD_naive = (log((E+F)/F) + (ANNRET - (SIGMAV1*SIGMAV1*0.5)))/SIGMAV1;
PD_naive = CDF("normal",-DD_naive);
drop F ANNRET _type_ _mode_ _errors_ E SIGMAD;
run;

/*---------------------------------------------------Method 3---------------------------------------------------*/
/*initial step of iteration*/
/*estimates V, initial guess of sigma V is sigma E*/
data merge_day;
set merge_day;
E = DE;
SIGMAV3 = SIGMAE;
V3 = E + F;
if nmiss(of E) then delete;
if nmiss(of F) then delete;
if nmiss(of SIGMAE) then delete;
keep CUSIP YEAR F DATE E ANNRET SIGMAE RF SIGMAV3 V3;
run;

/*merges by cusip and day for proc model*/
proc sort data = merge_day;
by CUSIP DATE;
run;


%macro mMethod3;
	/*set number of iterations for method 3*/
	%do n = 1 %to 8;

		/*solves for V, with the sigma V assumption*/
		proc model data = merge_day noprint converge = 0.001 newton;
		eq.equity = V3*CDF('normal',(log(V3/F)+ RF + SIGMAV3*SIGMAV3*0.5)/SIGMAV3) - exp(-1*RF)*F*CDF('normal',(log(V3/F) + RF + SIGMAV3*SIGMAV3*0.5)/SIGMAV3 - SIGMAV3) - E;
		solve V3 / out = solve3;
		by CUSIP DATE;
		id ANNRET F YEAR;
		quit;

		/*keeps only solved value of firm, cusip and date for merging*/
		data solve3;
		set solve3;
		keep V3 CUSIP DATE;
		run;

		/*drops previous value of firm estimation*/
		data merge_day;
		set merge_day;
		drop V3;
		run;

		/*sorts data for merge*/
		proc sort data = solve3;
		by CUSIP DATE;
		run;

		proc sort data = merge_day;
		by CUSIP DATE;
		run;

		/*merges solved value of firm with master data set*/
		/*does in name of solved proc model data to prevent overlap*/
		data solve3;
		merge solve3(in = a) merge_day(in = b);
		by CUSIP DATE;
		if a & b;
		run;

		/*lags V and cusip*/
		/*calculates returns on a per day basis using lagged values*/
		data solve3;
		set solve3;
		lag_cusip = lag(CUSIP);
		lag_V3 = lag(V3);
		if lag_cusip = CUSIP /*makes sure for same company*/
		then VRET = (V3 - lag_V3)/lag_V3;
		run;

		/*sorts data by year for value of firm returns volatility*/
		proc sort data = solve3;
		by CUSIP YEAR;
		run;

		/*calculates the value of firm returns volatility*/
		/*keeps only std deviation value from proc means*/
		proc means data = solve3 std NOPRINT;
		var VRET;
		by CUSIP YEAR;
		output out = std_vret std=;
		run;

		/*solves for new sigma V using std deviation value*/
		data std_vret;
		set std_vret;
		SIGMAV3_1 = sqrt(250)*VRET; /*assume 250 business days a year*/
		if nmiss(of SIGMAV3_1) then delete;
		keep CUSIP SIGMAV3_1 YEAR;
		run;

		/*sorts sigma V data set for merge with solved values*/
		proc sort data = std_vret;
		by CUSIP YEAR;
		run;

		proc sort data = solve3;
		by CUSIP YEAR;
		run;

		/*creates new master file*/
		/*will be used in next iteration, with new values*/
		data merge_day;
		merge solve3(in = a) std_vret(in = b);
		by CUSIP YEAR;
		if a & b;
		run;

		/*determines if the values are converging*/
		/*gets difference between sigma values*/
		data merge_day;
		set merge_day;
		SIGV_DIFF = abs(SIGMAV3 - SIGMAV3_1);
		if SIGV_DIFF < 0.0001 then check = 1;
		run;

		/*pulls converged values from the data*/
		data conv;
		set merge_day;
		if check = 1;
		SIGMAV3 = SIGMAV3_1;
		drop SIGMAV3_1 DLC DLTT FIC lag_cusip lag_V3;
		run;

		/*sorts data for merge with new data table*/
		proc sort data = conv;
		by CUSIP DATE;
		run;

		/*creates a data table that takes converged values*/
		data converge;
		merge converge conv;
		by CUSIP DATE;
		run;

		/*gets rid of converged values from the previous pass*/
		data merge_day;
		set merge_day;
		if check ne 1;
		SIGMAV3 = SIGMAV3_1;
		drop SIGMAV3_1 lag_cusip lag_V3;
		run;

	%end;
%mend;

/*runs macro for method 3*/
%mMethod3;

/*keeps needed variables, averages V per year*/
proc sql NOPRINT;
create table converge_sql as
select CUSIP, YEAR-1 as YEAR,
ANNRET, SIGMAE, SIGMAV3, F, RF,
mean(V3) as V3 /*averages the value of the firm on a yearly basis*/
from converge
group by CUSIP, YEAR;
quit;

/*gets values on a yearly basis*/
/*sorts for merge*/
proc sort data = converge_sql nodupkey;
by CUSIP YEAR;
run;

/*calculates DD and PD for method 3*/
data data_method3;
set converge_sql;
DD_iterative = (log(V3/F) + (ANNRET - SIGMAV3*SIGMAV3*0.5))/SIGMAV3;
PD_iterative = CDF('normal',-DD_iterative);
if nmiss(of DD_iterative) then delete;
run;

/*---------------------------------------------------Merge Methods---------------------------------------------------*/
/*orders data by cusip year for merge with method 1 and 2 values*/
proc sort data = data_method12;
by CUSIP YEAR;
run;

proc sort data = data_method3;
by CUSIP YEAR;
run;

/*merges method 3 DD/PD values with method 1 and DD/PD values*/
data data;
merge data_method3(in = a) data_method12(in = b);
by CUSIP YEAR;
if a & b;
keep CUSIP YEAR DD_naive DD_direct DD_iterative PD_naive PD_direct PD_iterative;
run;

/*opens pdf file, allows for input*/
/*remember to close file at end of program*/
/*set location of Ppath to desired location of pdf*/
ods pdf file = "&Ppath\Distance_to_Default_Data.pdf";

/*---------------------------------------------------Stats & Corr for DD and PD---------------------------------------------------*/
/*creates a data set for descriptive stats*/
data data_stats;
set data;
run;

/*sorts data for mean*/
proc sort data = data_stats;
by YEAR;
run;

/*descriptive stats for the DD and PD*/
proc means data = data_stats N mean p25 p50 p75 std min max;
title "Descriptive statistics per year for PD and DD";
by YEAR;
output out = data_stats;
run;

/*variables for correlation*/
%let corr_1 = DD_naive PD_naive;
%let corr_2 = DD_direct PD_direct;
%let corr_3 = DD_iterative PD_iterative;
%let corr_4 = DD_naive DD_direct DD_iterative;
%let corr_5 = PD_naive PD_direct PD_iterative;

/*macro for correlation of DD and PD data*/
%macro mCorrelation;
	%do xCorr = 1 %to 5;
		proc corr data = data;
		title "Correlation for DD and PD";
		var &&corr_&xCorr;
		run;
	%end;
%mend;

/*runs macro for input into pdf*/
%mCorrelation;

/*---------------------------------------------------Statistics and Comparisons plots---------------------------------------------------*/
/*sorts data by year for proc means*/
proc sort data = data;
by YEAR;
run;

/*gets percentile data for mean/percentiles plot*/
proc means data = data mean p25 p50 p75 NOPRINT;
var DD_naive DD_direct DD_iterative PD_naive PD_direct PD_iterative;
by YEAR;
output out = stats_plots (drop=_type_ _freq_) mean= p25= p50= p75= / autoname;
run;

/*plots the percentiles and mean of method 1*/
proc sgplot data = stats_plots;
title "DD Naive Method mean p25 p50 and p75, 1970 to 2015";
series x=YEAR y=DD_naive_p25;
series x=YEAR y=DD_naive_p50;
series x=YEAR y=DD_naive_p75;
series x=YEAR y=DD_naive_mean;
run;

/*plots the percentiles and mean of method 2*/
proc sgplot data = stats_plots;
title "DD Direct Method mean p25 p50 and p75, 1970 to 2015";
series x=YEAR y=DD_direct_p25;
series x=YEAR y=DD_direct_p50;
series x=YEAR y=DD_direct_p75;
series x=YEAR y=DD_direct_mean;
run;

/*plots the percentiles and mean of method 3*/
proc sgplot data = stats_plots;
title "DD Iterative Method mean p25 p50 and p75, 1970 to 2015";
series x=YEAR y=DD_iterative_p25;
series x=YEAR y=DD_iterative_p50;
series x=YEAR y=DD_iterative_p75;
series x=YEAR y=DD_iterative_mean;
run;

/*plots a comparison between mean DD values*/
proc sgplot data = stats_plots;
title "DD Mean Comparison";
series x=YEAR y=DD_iterative_mean;
series x=YEAR y=DD_naive_mean;
series x=YEAR y=DD_direct_mean;
run;

/*plots a comparison between mean PD values*/
proc sgplot data = stats_plots;
title "PD Mean Comparison";
series x=YEAR y=PD_iterative_mean;
series x=YEAR y=PD_naive_mean;
series x=YEAR y=PD_direct_mean;
run;

/*---------------------------------------------------Recession and Descriptive Stats---------------------------------------------------*/
/*sorts data for merge*/
proc sort data = data;
by YEAR;
run;

/*merges data for recession comparison*/
data rec;
merge data(in = a) rec(in = b);
by YEAR;
if a & b;
drop CUSIP; /*don't need company id anymore*/
run;

/*sorts for mean values on a yearly basis*/
proc sort data = rec;
by YEAR;
run;

/*gets recession mean for plot*/
proc means data = rec mean NOPRINT;
by YEAR;
output out = rec_plot mean=;
run;

/*removes year for descriptive stats, since stats by USREC*/
data rec_stats;
set rec;
drop YEAR;
run;

/*sorts by recession before descriptive stats*/
proc sort data = rec_stats;
by USREC;
run;

/*gets descriptive stats for recession and non recession years*/
/*prints stats into pdf*/
proc means data = rec_stats N mean p25 p50 p75 std min max;
title "Descriptive Statistics of DD and PD for Recession Years";
by USREC;
output out = rec_stats;
run;

/*---------------------------------------------------Plot Recession DD and PD---------------------------------------------------*/
/*set the graphics environment for gplot*/
goptions reset=all cback=white border htitle=12pt htext=10pt;

/*variables for plotting recession, baa and stress index*/
%let var_1 = DD_naive;
%let var_2 = PD_naive;
%let var_3 = DD_direct;
%let var_4 = PD_direct;
%let var_5 = DD_iterative;
%let var_6 = PD_iterative;

/*recession plot annotations*/
/*creates a red dot on data line for years a recession occurred*/
data rec_anno;
length function color $8;
retain xsys ysys '2' when 'a';
set rec_plot;
function = 'symbol';
x = YEAR;
size = 1;
if USREC = 1 then color = 'red';
else color = 'grey';
if USREC = 1 then text = 'dot';
output;
run;

%macro mRecPlot;
	%do xRec = 1 %to 6;
		/*changes y variable for annotation in plot*/
		data rec_anno;
		set rec_anno;
		y = &&var_&xRec;
		run;

		/*plotting recession information*/
		proc gplot data = rec_plot;
		title "&&var_&xRec per year with USREC data, 1970 to 2015";
		symbol interpol = join;
		plot &&var_&xRec*YEAR / annotate = rec_anno;
		run;
		quit;
	%end;
%mend;

/*---------------------------------------------------Prepare Baa Plot---------------------------------------------------*/
/*sorts data for merge*/
proc sort data = data;
by YEAR;
run;

/*merges data for baa comparison*/
data baa;
merge data(in = a) baa(in = b);
by YEAR;
if a & b;
drop CUSIP;
run;

/*sorts for average values per year*/
proc sort data = baa;
by YEAR;
run;

/*gets mean for plot*/
proc means data = baa mean NOPRINT;
by YEAR;
output out = baa_plot mean=;
run;

/*---------------------------------------------------Prepare Stress Plot---------------------------------------------------*/
/*sorts data for merge*/
proc sort data = data;
by YEAR;
run;

/*merges data for stress data comparison*/
/*will only keep years where there is CFSI data*/
/*so no need to worry about empty cells*/
data stress;
merge data(in = a) stress(in = b);
by YEAR;
if a & b;
drop CUSIP;
run;

/*sorts for mean and plot*/
proc sort data = stress;
by YEAR;
run;

/*gets mean for plot*/
proc means data = stress mean NOPRINT;
by YEAR;
output out = stress_plot mean=;
run;

/*---------------------------------------------------Plotting Macro for Baa and Stress---------------------------------------------------*/
/*sets up legends for stress and baa gplots*/
/*stress plot*/
legend1 origin=(30,90) pct mode=share;
legend2 origin=(30,85) pct mode=share;
/*baa plot*/
legend3 origin=(40,15) pct mode=share;
legend4 origin=(40,10) pct mode=share;

%macro mBaaStressPlot;

	%do xStress = 1 %to 6;
		/*stress plot*/
		proc gplot data = stress_plot;
		title "Stress Index and &&var_&xStress per year";
		symbol1 interpol = join c = red v = star h = 1;
		plot &&var_&xStress*YEAR / overlay legend = legend1;
		symbol2 interpol = join c = blue v = dot h = 1;
		plot2 CFSI*YEAR / overlay legend = legend2;
		run;
		quit;
	%end;

	%do xBaa = 1 %to 6;
		/*Baa plot*/
		proc gplot data = baa_plot;
		title "Baa and &&var_&xBaa per year, 1970 to 2015";
		symbol1 interpol = join c = red v = star h = 1;
		plot &&var_&xBaa*YEAR / overlay legend = legend3;
		symbol2 interpol = join c = blue v = dot h = 1;
		plot2 BAAFFM*YEAR / overlay legend = legend4;
		run;
		quit;
	%end;

%mend;

/*runs plotting macros*/
%mRecPlot;
%mBaaStressPlot;
ods pdf close; /*closes pdf after code has run*/

run;
