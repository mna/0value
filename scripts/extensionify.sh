#!/bin/bash

set -euo pipefail

for file in public/*; do
  if [[ -f ${file} ]]; then
    filename=$(basename "$file")
    extension="${filename##*.}"

    # extension is the same as filename if there is no extension
    if [[ ${extension} == ${filename} ]]; then
      if [[ ${filename} == "rss" ]]; then
        mv ${file} ${file}.xml
      else
        mv ${file} ${file}.html
      fi
    fi
  fi
done

