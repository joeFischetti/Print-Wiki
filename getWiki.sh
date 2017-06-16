#!/bin/bash
#This script polls the wiki (using a session cookie stored in 'cookies')
#and prints out every page to HTML files for hard-copy generation

wikiURL="http://some-wikipedia-name"

#set the file for the list of pageNames
pageNames="pageNames.txt"

#set the variable for the start time
startTime=$(date +"%T")

#set up and create a new output folder
output=wikiDump
mkdir $output

#apiRequestUrl is a request to the API for the list of every wiki page listed
# on the wiki.  Note, only 500 can come back at once
apiRequestUrl="$wikiURL/api.php?action=query&format=xml&list=allpages&aplimit=max"

#call it the first time and send the output to pages.xml.  Pipe it through xmllint so it isn't one
#giant line
curl $apiRequestUrl -b cookies | xmllint --format - > $output/pages.xml

#while pages.xml has lines, read them in, get rid of all the extra, and
# send the output to pageNames.  If we find "<allpages apcontinue=", it
# means we've gotten to the end of the file, and we'll need to run the curl
# again with "&apcontinue=foo" added to the end... without the quotes

#removes leading whitespaces on each line, and puts it in pagesTemp1.xml
sed -e 's/^[ \t]*//' $output/pages.xml > $output/pagesTemp1.xml

#Finds lines with <p ---- title=", and puts the remainder of the line in pagesTemp2.xml
awk 'match($0, /(<p.*title=")/) {print substr($0, RLENGTH+1)}' $output/pagesTemp1.xml > $output/pagesTemp2.xml

#Removes the closing quote/brackets from each line, puts it in the pageNames file
awk 'match($0, /(\"\/>)/) {print substr($0, 0, RSTART-1)}' $output/pagesTemp2.xml >> $output/$pageNames

#Check pagesTemp1 for the existence of a continue tag
while grep -q apcontinue $output/pagesTemp1.xml
do
        #on the line with the continue tag, get rid of all the extra parts so we just have the apcontinue=PAGE_NAME
        awk 'match($0, /(<allpages )/) {print substr($0, RLENGTH+1)}' $output/pagesTemp1.xml > $output/nextPageTemp
        awk 'match($0, /(\"\/>)/) {print substr($0, 0, RSTART-1)}' $output/nextPageTemp > $output/nextPage

        #Get rid of the quotes in the page name
        sed -i -e 's/\"//g' $output/nextPage

        #Replace spaces with underscores
        sed -i -e 's/ /_/g' $output/nextPage

        #Get the first line of nextPage, and put it in the variable nextPage
        nextPage=$(head -n 1 $output/nextPage)

        #Add nextPage to the end of the requestURL
        apiRequestUrl=$apiRequestUrl"&"$nextPage

        #Curl for the continue'd pagenames list
        curl $apiRequestUrl -b cookies | xmllint --format - > $output/pages.xml

        #Fix the formatting, overwrite Temp2, and add the page names to the name file
        sed -e 's/^[ \t]*//' $output/pages.xml > $output/pagesTemp1.xml
        awk 'match($0, /(<p.*title=")/) {print substr($0, RLENGTH+1)}' $output/pagesTemp1.xml > $output/pagesTemp2.xml
        awk 'match($0, /(\"\/>)/) {print substr($0, 0, RSTART-1)}' $output/pagesTemp2.xml >> $output/$pageNames
done

#reformat the whitespaces in the pageNames file so they have underscores instead
sed -i -e 's/ /_/g' $output/$pageNames

#iterator to keep track of how many pages we've saved
i=1

#iterator for appending a number for the html filename (since we only want 100 pages per file)
htmlPart=1

#Read a line from the pageName file
while read -r pageName
do
        #Every 100 pages, increment the filename ending, and set the counter back to 1
        if ! (($i % 100)); then
                htmlPart=$((htmlPart+1))
                i=1
        fi

        #get the current page name, and put it on the end of the url
        pageURL=$wikiURL/wiki/$pageName

        #get the current page, and store it in the right html file
        curl $pageURL -b cookies >> $output/full-$htmlPart.html

        #increment our counter
        i=$((i+1))

done < $output/$pageNames

#Status update
echo "Cleaning up"

#go into the output directory, and remove all our temp files
cd $output
rm -rf pages.xml pagesTemp1.xml pagesTemp2.xml $pagenames nextPage nextPageTemp pageNames.txt

#Status update
echo "Downloading all attached images from the server"

#Download the wiki's image directory, so we have images available
wget -rnH -A png,jpg,jpeg $wikiURL/images --load-cookies cookies

#fix the links in the html file so they point to the local images folder
#reset the iterator
i=1

#run a loop on the html files
while (($i <= $htmlPart))
do
        sed -i -e 's/src=\"\/images/src=\"images/g' full-$i.html
        i=$((i+1))
done

#Set the end time
endTime=$(date +"%T")

#jump back up a level
cd ../

#Status update, with start and end times
echo "Complete.  Started at $startTime finished at $endTime"

#Print out information about the html files we created
ls -lh $output/full.*
