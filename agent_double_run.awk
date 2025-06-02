BEGIN {
	OFS=","
	if ( outdir=="") {
		outdir="."
	}
	if ( testid == "") {
		testid=".*"
	}
	print outdir
	print testid
	test_end_times_header="test_id,test_type,report_window,test_end_date_time,wire_time" 
	logresults_begin_upload_header="upload_time,test_id,report_window"
	logresults_end_upload_header="upload_time,test_id,report_window,upload_length,span,success"

	test_end_times_file=outdir "/test_end_times.csv"
	logresults_upload_begin_file=outdir "/logresults_upload_begin.csv"
	logresults_upload_end_file=outdir "/logresults_upload_end.csv"
	logresults_upload_retry__file=outdir "/logresults_upload_retry.csv"
	print test_end_times_header > test_end_times_file
	print logresults_begin_upload_header > logresults_upload_begin_file
	print logresults_end_upload_header > logresults_upload_end_file
}

/TEST-END/ {
	
	if ( $0 ~ testid) {
		for(i = 1; i < NR; i++) {
			if ( $i ~ /id=/) {
				test_id=$i
				gsub("id=|,|S|I","",test_id)
			} else if ( $i ~ /rpt-window=/ ) {
				report_window=$i" "$(i+1)
				gsub("rpt-window=|,","",report_window)
				split(report_window, fields," ")
				d=fields[1]
				t=fields[2]
				split(d,date_fields,"/")
				split(t,time_fields,":")
				report_window=date_fields[3]date_fields[1]date_fields[2]time_fields[1]time_fields[2]
			} else if ( i == 8 ) {
				test_type=$i
				gsub(",","",test_type)
			} else if ( i == 1 ) {
				test_end_date_time=$1" "$2
			} else if ( $i ~ /total-sec/ ) {
				wire_time=$i
				gsub("total-sec=|,","",wire_time)
			}
		}
		print test_id,test_type,report_window,test_end_date_time,wire_time >> test_end_times_file
		print test_id,test_type,report_window,test_end_date_time,wire_time 
	}
}

/RESULTS UPLOAD/ {
	if ( $0 ~ testid ) {
		for(i = 1; i < NR; i++) {
			if ( i == 1 ) {
				upload_time=$1" "$2
			} else if ( $i ~ /w=/ ) {
				report_window=$i
				gsub("w=|,","",report_window)
			} else if ($i ~ /id=/) {
				test_id=$i
				gsub("id=|,","",test_id)
			} else if ($i ~ /len=/) {
				upload_length=$i
				gsub("len=|,", "", upload_length)
			} else if ( $i ~ /span=/) {
				span=$i
				gsub("span=|,","",span)
			} else if ( $i ~ /success=/ ) {
				success=$i
				gsub("success=|,","",success)
			}
		}
		if ( $0 ~ "BEGIN" ) {
			print upload_time,test_id,report_window >> logresults_upload_begin_file
			print upload_time,test_id,report_window 
		} else if ( $0 ~ "END") {
			print upload_time,test_id,report_window,upload_length,span,success >> logresults_upload_end_file
			print upload_time,test_id,report_window,upload_length,span,success 
		} else {
			print "RETRY TO BE IMPLEMENTED"
		}
	}
}

