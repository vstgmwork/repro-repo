#!/usr/bin/awk -f

#
# process_logs.awk
#
# Description:
#   This AWK script scans log files for lines containing "MachineMetricsHarvester",
#   parses the key-value metrics within those lines, and exports the
#   specified data to a CSV format.
#
# Usage:
#   awk -f process_logs.awk your_log_file1.log [your_log_file2.log ...] > output.csv
#

# The BEGIN block is executed once before any lines are read from the input files.
BEGIN {
    # Set the Output Field Separator to a comma for CSV formatting.
    OFS = ","

    # Print the header row for the CSV file. This defines the columns.
    print "Timestamp", \
          "LastBootTime", \
          "StartupTimeUTC", \
          "SystemMemoryBytesPercentage(Used)", \
          "SystemCpuPercentage", \
          "TotalCDiskSpaceUsed%", \
          "ProcessThreadCount", \
          "ProcessHandleCount", \
          "UserName", \
          "ProductVersion", \
          "IpAddress", \
          "DnsAddress" > "instance_utilization_details.csv"
}

# This main block is executed for every input line that contains the string "MachineMetricsHarvester".
/MachineMetricsHarvester/ {
    # Extract the timestamp, which consists of the first two fields (date and time).
    timestamp = $1 " " $2

    # Create an associative array to store the metrics extracted from the log line.
    # 'delete metrics' ensures the array is empty for each new log line processed.
    delete metrics

    # Copy the entire current line ($0) into a variable for manipulation.
    line_content = $0

    # Use the match() function to find the substring containing the metrics.
    # The metrics are enclosed by "[metrics, " at the start and "])" at the end.
    if (match(line_content, /\[metrics, (.*)\]\)/)) {
        # Extract the matched substring containing all key-value pairs.
        # RSTART and RLENGTH are built-in variables set by match() that give the
        # start position and length of the matched string. We adjust them to
        # exclude the outer brackets and prefixes.
        metrics_data = substr(line_content, RSTART + 10, RLENGTH - 13)

        # Split the metrics data string into an array of pairs using " | " as the delimiter.
        split(metrics_data, pairs, / \| /)

        # Iterate through the array of key-value pairs.
        for (i in pairs) {
            # Find the position of the first colon ":" in the pair string.
            # This is more robust than splitting, in case a value contains a colon.
            sep_pos = index(pairs[i], ": ")
            if (sep_pos > 0) {
                # Extract the key (the part before the colon).
                key = substr(pairs[i], 1, sep_pos - 1)
                # Extract the value (the part after the colon and space).
                value = substr(pairs[i], sep_pos + 2)

                # Store the extracted key and value in our associative array.
                metrics[key] = value
            }
        }

        # Print the final CSV row by accessing the values from the 'metrics' array
        # in the predefined order. The Output Field Separator (OFS) will place
        # commas between them automatically.
        print timestamp, \
              metrics["LastBootTime"], \
              metrics["StartupTimeUTC"], \
              metrics["SystemMemoryBytesPercentage(Used)"], \
              metrics["SystemCpuPercentage"], \
              metrics["TotalCDiskSpaceUsed%"], \
              metrics["ProcessThreadCount"], \
              metrics["ProcessHandleCount"], \
              metrics["UserName"], \
              metrics["ProductVersion"], \
              metrics["IpAddress"], \
              metrics["DnsAddress"] >> "instance_utilization_details.csv"
    }
}
