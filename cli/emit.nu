# Print data to stdout: a table in a terminal, JSON when piped.
export def main []: any -> nothing {
    let data = $in
    print (if (is-terminal --stdout) { $data } else { $data | to json })
}
