#!/bin/bash

# ===================================================================================
#
# Shell Script to Automate Log Extraction and Analysis
#
# Description:
# This script finds all `.log.txz` files in the current directory and performs
# the following actions for each one:
#   1. Creates a new directory named after the log file (without the extension).
#   2. Extracts the contents of the `.txz` archive into this new directory.
#   3. Runs an AWK script on the extracted log files to generate multiple CSVs.
#   4. Runs a Python script to combine the generated CSVs into a single Excel file.
#
# Prerequisites:
#   - tar, xz-utils (for .txz extraction)
#   - gawk (GNU awk)
#   - python3, pip3
#   - Python libraries: pandas, openpyxl (`pip3 install pandas openpyxl`)
#
# ===================================================================================

# --- Script Configuration ---
# Names of the temporary script files that will be created.
AWK_SCRIPT_NAME="log_analysis.awk"
PYTHON_SCRIPT_NAME="combine_csv.py"

# --- Embedded AWK Script ---
# A "here document" (cat <<'EOF' ... EOF) is used to embed the AWK script.
# This avoids needing a separate file.
cat <<'EOF' > "$AWK_SCRIPT_NAME"
# ==============================================================================
# AWK Script for Parsing and Analyzing Log Files
# ==============================================================================
# This script processes log files, extracts various metrics and test data,
# and outputs the structured information into multiple CSV files for analysis.
# It handles different log entry formats, correlates start and end events for
# tests, and parses system utilization metrics.
#
# Usage: awk -f log_analysis.awk cpsns/* commeng/* cronlog/* testeng/* # ==============================================================================

# The BEGIN block is executed once before any lines from the input file are read.
# It's used for initialization tasks, such as setting variables and printing headers.
BEGIN {
    # Set the Output Field Separator to a comma for CSV formatting.
    OFS = ","

    # --- Create CSV files and write their headers ---
    # The '>' operator creates/truncates the file and writes the header.
    # The '>>' operator will be used later to append data rows.

    # Header for performance test data, including web vital metrics from cpsns logs.
    print "start_date_time", "test_id", "monitor", "report_window", "record_id", "end_date_time", "total_test_time", "total-sec", "dom-sec", "render-sec", "doc-complete-sec", "title-sec", "fps", "fcp", "fp", "tti", "vct", "lcp", "cls", "wire-sec", "client-sec", "act-rt", "exp-rt" > "hawk_test_start_end.csv"

    # Header for general test execution times from testeng logs.
    print "start_date_time", "end_date_time", "total_test_time", "test_id", "monitor_type", "report_window", "test_record_id" > "testeng_test_times.csv"

    # Header for system health and memory analysis from sns defib logs.
    print "Timestamp,Agent Service Status,CommEng Status,Total Memory (KB),Used Memory (KB),Available Memory (KB),Free Memory Percentage,CommEng PID,TxEng PID,TestEng PID" > "sns_defib_analysis.csv"

    # Header for commeng log test times.
    print "date_time", "test_id", "test_type", "report_time" > "commeng_test_time.csv"

    # Header for machine/instance resource utilization details from commeng logs.
    print "Timestamp", "LastBootTime", "StartupTimeUTC", "SystemMemoryBytesPercentage(Used)", "SystemCpuPercentage", "TotalCDiskSpaceUsed%", "ProcessThreadCount", "ProcessHandleCount", "UserName", "ProductVersion", "IpAddress", "DnsAddress" > "instance_utilization_details.csv"
}

# --- Block for Parsing Communication Engine Forwarder Logs ---
# This block triggers on lines related to the SimpleHttpsForwarder.
/<SimpleHttpsForwarder> Calling BuildOriginalRequestResponse/ {
    # Match and extract the full timestamp (YYYY-MM-DD HH:MM:SS.ms).
    if (match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}/, ts_arr)) {
        ts = ts_arr[0] # Store the matched timestamp.
        # Match and extract the content within "CPTID: [...]".
        if (match($0, /CPTID: \[([^]]+)\]/, arr)) {
            cptid_data = arr[1] # Store the captured JSON-like data.
            # Clean up the data: remove curly braces and backslashes.
            gsub(/[\\{}]/, "", cptid_data)
            # Replace JSON keys with a comma to create a delimited string.
            gsub(/"t":|,"s":/, ",", cptid_data)
            # Remove any leading comma that might result from the substitution.
            sub(/^,/, "", cptid_data)
            # Split the cleaned string into an array of data points.
            lines = split(cptid_data, data, ",")
            # Loop through the data array, processing 3 items at a time.
            for (i = 1; i <= lines; i += 3) {
                # Create a unique report time identifier by concatenating timestamp and data.
                report_time = ts data[i]
                # Sanitize the report_time to be purely numeric.
                gsub(/[^0-9]/, "", report_time)
                # Append the extracted data to the commeng_test_time.csv file.
                print ts "," data[i] "," data[i+1] "," report_time >> "commeng_test_time.csv"
            }
        }
    }
}


# --- Block for Correlating TEST-START and TEST-END Events (Hawk Tests) ---

# This block executes for lines containing "TEST-START".
/TEST-START/ {
    filename = FILENAME; # Store the current log file name.
    log_time = $1 " " $2  # Capture the log timestamp (date and time).
    # Initialize variables for test details.
    test_id = ""
    monitor = ""
    report_window = ""

    # Loop through the fields of the line starting from the 4th field.
    for (i = 4; i <= NF; i++) {
        # Extract the test ID.
        if ($i ~ /^id=/) {
            test_id = $i
            gsub("id=", "", test_id) # Remove the "id=" prefix.
            sub(/^[SI]/, "", test_id) # Remove leading 'S' or 'I'.
            gsub(/,/, "", test_id) # Remove any commas.
            
            # The monitor name often follows the ID.
            if ((i+1) <= NF) {
                monitor = $(i+1)
                gsub(/,/, "", monitor) # Remove commas.
            }
        # Extract the report window.
        } else if ($i ~ /^rpt-window=/) {
            report_window = $(i+1) # The window value is the next field.
            gsub(/rpt-window=|,/, "", $i) # Clean the key field.
            report_window = $i " " report_window # Combine date and time.
            gsub(/,/, "", report_window) # Remove commas.
            i++ # Increment i to skip the next field as it's already processed.
        }
    }
    
    # Create a unique record ID by concatenating the report window and test ID.
    record_id = report_window test_id
    # Sanitize the record_id by removing special characters.
    gsub(/[\/: ]/, "", record_id)
    
    # Store the parsed start-time data in an associative array `data`.
    # The unique `record_id` is the key. This allows us to find this data
    # when we encounter the corresponding TEST-END line.
    data[record_id] = log_time "," test_id "," monitor "," report_window "," record_id
}

# This block executes for lines containing "TEST-END".
/TEST-END/ {
    filename = FILENAME;
    end_date_time = $1 " " $2  # Capture the log timestamp for the end event.
    # Initialize variables.
    test_id = ""
    monitor = ""
    report_window = ""
    # Initialize all performance metrics to empty strings.
    total_sec = dom_sec = render_sec = doc_complete_sec = title_sec = fps = ""
    fcp = fp = tti = vct = lcp = cls = wire_sec = client_sec = act_rt = exp_rt = ""
    
    # Loop through the fields to parse test details and performance metrics.
    for (i = 4; i <= NF; i++) {
        # Extract test ID and report window, same logic as in TEST-START.
        if ($i ~ /^id=/) {
            test_id = $i
            gsub("id=", "", test_id)
            sub(/^[SI]/, "", test_id)
            gsub(/,/, "", test_id)
        } else if ($i ~ /^rpt-window=/) {
            report_window = $(i+1)
            gsub(/rpt-window=|,/, "", $i)
            report_window = $i " " report_window
            gsub(/,/, "", report_window)
            i++
        # This condition matches all key=value performance metrics.
        } else if ($i ~ /-sec=/ || $i ~ /^fps=/ || $i ~ /^fcp=/ || $i ~ /^fp=/ || $i ~ /^tti=/ || $i ~ /^vct=/ || $i ~ /^lcp=/ || $i ~ /^cls=/ || $i ~ /^wire-sec=/ || $i ~ /^client-sec=/ || $i ~ /^act-rt=/ || $i ~ /^exp-rt=/) {
            # Split the field by "=" to separate the key and value.
            split($i, kv, "=")
            metric = kv[1]
            value = kv[2]
            gsub(/,/, "", value) # Clean the value.

            # Assign the value to the corresponding metric variable.
            if (metric == "total-sec") total_sec = value
            else if (metric == "dom-sec") dom_sec = value
            else if (metric == "render-sec") render_sec = value
            else if (metric == "doc-complete-sec") doc_complete_sec = value
            else if (metric == "title-sec") title_sec = value
            else if (metric == "fps") fps = value
            else if (metric == "fcp") fcp = value
            else if (metric == "fp") fp = value
            else if (metric == "tti") tti = value
            else if (metric == "vct") vct = value
            else if (metric == "lcp") lcp = value
            else if (metric == "cls") cls = value
            else if (metric == "wire-sec") wire_sec = value
            else if (metric == "client-sec") client_sec = value
            else if (metric == "act-rt") act_rt = value
            else if (metric == "exp-rt") exp_rt = value
        }
    }
    
    # Recreate the unique record_id to match the one from TEST-START.
    record_id = report_window test_id
    gsub(/[\/: ]/, "", record_id)
    
    # Check if a corresponding TEST-START was found and stored.
    if (record_id in data) {
        # Retrieve the start-time data.
        split(data[record_id], fields, ",")
        start_date_time = fields[1]
        
        # --- Calculate Total Test Time ---
        # Use the external 'date' command to convert timestamps to epoch seconds
        # with millisecond precision. This is a common awk technique for date math.
        cmd = "date -d '" start_date_time "' +%s.%3N"
        cmd | getline start_epoch # Execute command and read output into start_epoch.
        close(cmd) # Close the pipe.
        
        cmd = "date -d '" end_date_time "' +%s.%3N"
        cmd | getline end_epoch
        close(cmd)
        
        # Calculate the difference and format to 3 decimal places.
        total_test_time = sprintf("%.3f", end_epoch - start_epoch)
        
        # Print the combined start data, end time, calculated duration, and all metrics.
        print data[record_id], end_date_time, total_test_time, total_sec, dom_sec, render_sec, doc_complete_sec, title_sec, fps, fcp, fp, tti, vct, lcp, cls, wire_sec, client_sec, act_rt, exp_rt >> "hawk_test_start_end.csv"
        
        # Delete the entry from the array to free memory and prevent reprocessing.
        delete data[record_id]
    }
}


# --- Block for Correlating TestExecutionBegin and TestExecutionEnd Events ---

# This block triggers on "TestExecutionBegin" log lines.
/TestExecutionBegin/ {
    filename = FILENAME
    split($2, tempData, ",") # Time is in the second field.
    min_time = tempData[1]
    date_time = substr($1, index($1, ".") + 1) # Extract date part from first field.
    start_date_time = date_time " " min_time # Combine to full timestamp.
    
    testID = $7
    gsub(/[^0-9]/, "", testID) # Sanitize test ID to be numeric.
    monitorSet = gensub(/[^0-9]*/, "", "g", $8) # Extract numbers from monitor set.

    # Extract the report window time using a regex match.
    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr)
    actualRuntime = (arr[1] != "") ? arr[1] : ""

    # --- Convert 12-hour AM/PM time to 24-hour format ---
    gsub(/(am|pm)/i, toupper(substr(actualRuntime, length(actualRuntime) - 1)), actualRuntime)
    split(actualRuntime, datetime, " ")
    split(datetime[2], time_parts, ":")

    hour = time_parts[1] + 0
    minute = time_parts[2]
    second = time_parts[3]
    am_pm = tolower(datetime[3])

    if (am_pm == "pm" && hour != 12) hour += 12
    if (am_pm == "am" && hour == 12) hour = 0
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, second)
    formattedRuntime = datetime[1] " " converted_time

    # Create a unique record ID and store the start data.
    record_id = formattedRuntime testID
    gsub(/[^0-9]/, "", record_id)
    data[record_id] = start_date_time "," testID "," monitorSet "," formattedRuntime "," record_id
}

# This block triggers on "TestExecutionEnd" log lines.
/TestExecutionEnd/ {
    filename = FILENAME
    # Parsing logic is similar to TestExecutionBegin.
    split($2, tempData, ",")
    min_time = tempData[1]
    date_time = substr($1, index($1, ".") + 1)
    end_date_time = date_time " " min_time
    testID = $7
    gsub(/[^0-9]/, "", testID)
    monitorSet = gensub(/[^0-9]*/, "", "g", $8)

    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr)
    actualRuntime = (arr[1] != "") ? arr[1] : ""

    # Convert time to 24-hour format.
    gsub(/(am|pm)/i, toupper(substr(actualRuntime, length(actualRuntime) - 1)), actualRuntime)
    split(actualRuntime, datetime, " ")
    split(datetime[2], time_parts, ":")

    hour = time_parts[1] + 0
    minute = time_parts[2]
    second = time_parts[3]
    am_pm = tolower(datetime[3])

    if (am_pm == "pm" && hour != 12) hour += 12
    if (am_pm == "am" && hour == 12) hour = 0
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, second)
    formattedRuntime = datetime[1] " " converted_time

    # Recreate the record ID to find the matching start event.
    record_id = formattedRuntime testID
    gsub(/[^0-9]/, "", record_id)

    # If a matching start event exists...
    if (record_id in data) {
        split(data[record_id], fields, ",")
        start_date_time = fields[1]

        # Calculate total test time using the 'date' command.
        cmd = "date -d \"" start_date_time "\" +%s.%3N"
        cmd | getline start_epoch
        close(cmd)

        cmd = "date -d \"" end_date_time "\" +%s.%3N"
        cmd | getline end_epoch
        close(cmd)

        total_test_time = sprintf("%.3f", end_epoch - start_epoch)
        # Append the correlated data to the test times CSV.
        print start_date_time "," end_date_time "," total_test_time "," testID "," monitorSet "," formattedRuntime "," record_id >> "testeng_test_times.csv"

        # Clean up the stored data.
        delete data[record_id]
    }
}


# --- Block for Parsing System Health / Defibrillator Logs ---
# This section parses a multi-line block of system health information.

# This pattern matches the timestamp line that starts a health block.
/^[0-9]{2}\/[0-9]{2}\/[0-9]{4}/ {
    timestamp = $1 " " $2 # Capture timestamp.
    in_block = 1 # Set a flag to indicate we are inside a health block.
    # Reset all variables for this block.
    agent_status = commeng_status = total_mem = used_mem = available_mem = ""
    free_mem_pct = commeng_pid = txeng_pid = testeng_pid = ""
}

# The following patterns match specific lines within the health block.
# 'getline' is used to read the *next* line, which contains the value.
/^Checking for Agent service hang/ { getline; agent_status = $1 }
/^Checking for sustained Harmony CommEng not running/ { getline; commeng_status = $1 }
# Parse memory stats from the "Mem:" line.
/^Mem:/ {
    total_mem = $2
    used_mem = $3
    available_mem = $7
}

# Parse Process IDs (PIDs) for specific DLLs.
/CommEng\.dll/ { commeng_pid = $2 }
/TxEng\.dll/ { txeng_pid = $2 }
/TestEng\.dll/ { testeng_pid = $2 }

# This pattern marks the end of the health block.
/^Free Memory percentage:/ {
    # Only proceed if we are inside a block (the 'in_block' flag is set).
    if (in_block) {
        # Calculate the free memory percentage.
        free_mem_pct = int($4 * 100)
        # Print the complete, collected record for this block.
        print timestamp "," agent_status "," commeng_status "," total_mem "," used_mem "," available_mem "," free_mem_pct "," commeng_pid "," txeng_pid "," testeng_pid >> "sns_defib_analysis.csv"
        # Reset the flag to avoid printing duplicates until a new block starts.
        in_block = 0
    }
}


# --- Block for Parsing Machine Metrics Harvester Logs ---
# This block parses a single line containing multiple key-value metrics.
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
            # Find the position of the first ": " separator in the pair string.
            # This is more robust than splitting by ":" in case a value also contains a colon.
            sep_pos = index(pairs[i], ": ")
            if (sep_pos > 0) {
                # Extract the key (the part before the separator).
                key = substr(pairs[i], 1, sep_pos - 1)
                # Extract the value (the part after the separator).
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
EOF

# --- Embedded Python Script ---
cat <<'EOF' > "$PYTHON_SCRIPT_NAME"
import pandas as pd
import os

def combine_csv_to_excel():
    """
    Finds all CSV files in the current directory, reads each one, converts
    date columns, and saves it as a separate sheet in a single Excel file.
    """
    # List of CSV files generated by the awk script
    csv_files = [
        "hawk_test_start_end.csv",
        "testeng_test_times.csv",
        "sns_defib_analysis.csv",
        "commeng_test_time.csv",
        "instance_utilization_details.csv"
    ]
    
    # --- NEW: Map CSV files to their respective date/timestamp columns ---
    date_columns_map = {
        "hawk_test_start_end.csv": ["start_date_time", "end_date_time"],
        "testeng_test_times.csv": ["start_date_time", "end_date_time"],
        "sns_defib_analysis.csv": ["Timestamp"],
        "commeng_test_time.csv": ["date_time"],
        "instance_utilization_details.csv": ["Timestamp", "LastBootTime", "StartupTimeUTC"]
    }
    
    output_excel_file = 'log_analysis_summary.xlsx'

    try:
        # Create a Pandas Excel writer using openpyxl as the engine.
        with pd.ExcelWriter(output_excel_file, engine='openpyxl') as writer:
            print(f"Creating Excel file: {output_excel_file}")

            # Loop through the list of CSV files
            for csv_file in csv_files:
                # Check if the CSV file exists before trying to read it
                if os.path.exists(csv_file):
                    try:
                        # Read the CSV file into a pandas DataFrame
                        df = pd.read_csv(csv_file)
                        
                        # --- NEW: Check for and convert date columns ---
                        if csv_file in date_columns_map:
                            date_cols = date_columns_map[csv_file]
                            for col in date_cols:
                                if col in df.columns:
                                    # Convert column to datetime, coercing errors to NaT (Not a Time)
                                    df[col] = pd.to_datetime(df[col], errors='coerce')
                                    print(f"  - Converted column '{col}' to datetime format.")

                        # Create a clean sheet name from the CSV filename
                        sheet_name = os.path.splitext(csv_file)[0][:31]
                        
                        # Write the DataFrame to a specific sheet in the Excel file
                        df.to_excel(writer, sheet_name=sheet_name, index=False)
                        
                        print(f"  - Added sheet '{sheet_name}' from '{csv_file}'")

                    except Exception as e:
                        print(f"  - Could not process {csv_file}. Error: {e}")
                else:
                    print(f"  - Skipping '{csv_file}' because it was not found.")
        
        print(f"\nSuccessfully combined CSV files into '{output_excel_file}'")

    except Exception as e:
        print(f"An error occurred while creating the Excel file: {e}")

if __name__ == "__main__":
    combine_csv_to_excel()
EOF

# --- Main Processing Logic ---

# Function to print messages with a timestamp
log_with_timestamp() {
    # Formats the output of the 'date' command and prepends it to the message ($1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check for all required command-line tools and Python libraries
check_prerequisites() {
    log_with_timestamp "Checking for required tools..."
    local missing_tools=0

    # Check for command-line tools
    local tools=("tar" "xz" "gawk" "python3" "pip3")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_with_timestamp "   - ❌ ERROR: Command '$tool' not found. Please install it."
            missing_tools=1
        else
            log_with_timestamp "   - ✅ Found: $tool"
        fi
    done

    # Check for Python libraries
    if command -v "python3" &> /dev/null; then
        log_with_timestamp "Checking for required Python libraries..."
        if ! python3 -c "import pandas; import openpyxl" &> /dev/null; then
            log_with_timestamp "   - ❌ ERROR: Python libraries 'pandas' or 'openpyxl' not found."
            log_with_timestamp "   - Please install them using: pip3 install pandas openpyxl"
            missing_tools=1
        else
            log_with_timestamp "   - ✅ Found: pandas, openpyxl"
        fi
    fi

    # Exit if any tool is missing
    if [ "$missing_tools" -ne 0 ]; then
        log_with_timestamp "Aborting due to missing prerequisites."
        exit 1
    fi
    log_with_timestamp "All prerequisites are met."
    log_with_timestamp "--------------------------------"
}

# --- SCRIPT START ---

# 1. Check if all prerequisites are met before starting
check_prerequisites

log_with_timestamp "Starting log processing..."

# 2. Loop through all files ending with .log.txz in the current directory
for file in *.log.txz; do
    # Check if the file exists to avoid errors if no files are found
    [ -e "$file" ] || { log_with_timestamp "No .log.txz files found to process. Exiting."; exit 0; }

    # Derive the folder name by removing the '.log.txz' extension
    folder_name="${file%.log.txz}"

    log_with_timestamp "▶️  Processing file: $file"

    # Create a directory for the extracted files
    log_with_timestamp "   - Creating directory: $folder_name"
    mkdir -p "$folder_name"

    # Extract the archive into the new directory
    log_with_timestamp "   - Extracting archive..."
    if tar -xJf "$file" -C "$folder_name"; then
        log_with_timestamp "   - Extraction successful."
    else
        log_with_timestamp "   - ❌ ERROR: Failed to extract $file. Skipping."
        continue # Skip to the next file
    fi

    # Navigate into the new directory
    cd "$folder_name" || { log_with_timestamp "   - ❌ ERROR: Could not cd into $folder_name. Skipping."; cd ..; continue; }

    # Run the AWK script to generate CSV files
    log_with_timestamp "   - Running AWK script to generate CSVs..."
    # The awk script is in the parent dir, so we use ../
    # The log files are in subdirectories like 'cpsns', 'commeng', etc.
    # We use */* to process all files in all subdirectories.
    if awk -f "../$AWK_SCRIPT_NAME" */* 2>/dev/null; then
        log_with_timestamp "   - AWK script completed."
    else
        log_with_timestamp "   - ❌ WARNING: AWK script encountered an error or no log files were found to process."
    fi

    # Run the Python script to combine CSVs into an Excel file
    log_with_timestamp "   - Running Python script to generate Excel file..."
    # The python script's own output is not timestamped, but this line will show when it starts.
    if python3 "../$PYTHON_SCRIPT_NAME"; then
        log_with_timestamp "   - Python script completed successfully."
    else
        log_with_timestamp "   - ❌ WARNING: Python script encountered an error."
    fi

    # Return to the parent directory for the next loop iteration
    cd ..
    log_with_timestamp "✅ Finished processing $file"
    log_with_timestamp "--------------------------------"
done

# --- Cleanup ---
# Remove the temporary script files created by this script
rm -f "$AWK_SCRIPT_NAME" "$PYTHON_SCRIPT_NAME"

log_with_timestamp "All log files have been processed."

