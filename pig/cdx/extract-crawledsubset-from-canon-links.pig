/*
 * Copyright 2013 Internet Archive
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. 
 */

/* Input: Canonicalized link data (src,timestamp,dst,path,linktext)
 * Input: CDX (wayback index files for the collection(s))
 * Output: Canonicalized link data where every dst is in the CDX (i.e. dst has been crawled)
 */

%default I_CANON_LINKS_DATA_DIR '/search/nara/congress112th/analysis/canon-wat-links.gz/';
%default I_CDX_DIR '/search/nara/congress112th/cdx/';
%default O_CRAWLED_CANON_LINKS_DATA_DIR '/search/nara/congress112th/analysis/links-from-wats-only-crawled-resources.gz';

--CDH4
--REGISTER lib/webarchive-commons-jar-with-dependencies.jar;

--CDH3
--REGISTER lib/ia-web-commons-jar-with-dependencies-CDH3.jar;

REGISTER lib/ia-porky-jar-with-dependencies.jar;
DEFINE SURTURL org.archive.porky.SurtUrlKey();

Links = LOAD '$I_CANON_LINKS_DATA_DIR' as (src:chararray, timestamp:chararray, dst:chararray, path:chararray, linktext:chararray);
CDXLines = LOAD '$I_CDX_DIR' using PigStorage(' ') AS (curl:chararray, ts:chararray, ourl:chararray);

CrawledUrls = foreach CDXLines GENERATE SURTURL(ourl) as url;
CrawledUrls = DISTINCT CrawledUrls;

--grab only links where dst has been crawled
CrawledLinks = JOIN Links BY dst, CrawledUrls by url;
CrawledLinks = FOREACH CrawledLinks GENERATE Links::src, Links::timestamp, Links::dst, Links::path, Links::linktext;

STORE CrawledLinks into '$O_CRAWLED_CANON_LINKS_DATA_DIR';
