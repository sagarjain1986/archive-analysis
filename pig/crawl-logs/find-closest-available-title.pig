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

/* Input: A list of URLs (original) that need a title assigned (from the "closest" URL that contains one)
 * Input: A mapping of the crawled URLs to unique integers IDs (crawllogid.map)
 * Input: A mapping of the crawllogid to the complete hoppath from the crawler (generated by Giraph)
 * Input: A mapping of the url (SURT) to the title text 
 * Output: Lines containing the url (original) and the assigned title from the "closest" URL that contained it 
 */


%default I_ORIGURL_WITHOUT_TITLES_DIR '/search/nara/congress112th/analysis/video-orig-urls.txt';
%default I_CRAWLLOG_ID_MAP_DIR '/search/nara/congress112th/analysis/crawllogid.map';
%default I_CRAWLLOGID_HOPPATHFROMCRAWLER_DIR '/search/nara/congress112th/analysis/crawllogid.hoppathfromcrawler';
%default I_URL_TITLE_DIR '/search/nara/congress112th/analysis/url.title.gz';
%default O_ORIGURL_CLOSESTVIAORIGURL_CLOSESTVIATITLE_HOPPATHFROMCLOSESTVIA_NUMHOPSROMCLOSESTVIA '/search/nara/congress112th/analysis/videos.origurl-closestviaorigurl-closestviatitle-hoppathfromclosestvia-numhopsfromclosestvia.gz';
--CDH4
--REGISTER lib/ia-web-commons-jar-with-dependencies-CDH4.jar;

--CDH3
REGISTER lib/ia-web-commons-jar-with-dependencies-CDH3.jar;
REGISTER lib/expandCrawlerHopPath.py using jython as EXPANDHOPS;

REGISTER lib/pigtools.jar;
DEFINE SURTURL pigtools.SurtUrlKey();

OrigUrlsWithoutTitles = LOAD '$I_ORIGURL_WITHOUT_TITLES_DIR' AS (origurl:chararray);
CrawlLogIdMap = LOAD '$I_CRAWLLOG_ID_MAP_DIR' as (crawllogid:chararray, crawllogurl:chararray);
CrawlLogIdCrawlerHoppath = LOAD '$I_CRAWLLOGID_HOPPATHFROMCRAWLER_DIR' as (crawllogid:chararray, hoppathfromcrawler:chararray);
UrlTitles = LOAD '$I_URL_TITLE_DIR' AS (url:chararray, title:chararray);


--Find the corresponding crawllogid for the input URLs
Joined = Join OrigUrlsWithoutTitles BY origurl, CrawlLogIdMap BY crawllogurl;
OrigUrlsWithIds = FOREACH Joined GENERATE OrigUrlsWithoutTitles::origurl as origurl, CrawlLogIdMap::crawllogid as crawllogid;

--now find the corresponding hoppathinfo
Joined = Join OrigUrlsWithIds BY crawllogid, CrawlLogIdCrawlerHoppath BY crawllogid;
OrigUrlsWithCrawlerHopPath = FOREACH Joined GENERATE OrigUrlsWithIds::origurl as origurl, 
						     OrigUrlsWithIds::crawllogid as crawllogid, 
						     CrawlLogIdCrawlerHoppath::hoppathfromcrawler as hoppathfromcrawler;

--Expand the hop path to get per hop info
OrigUrlsWithHopInfo = FOREACH OrigUrlsWithCrawlerHopPath GENERATE origurl as origurl:chararray, EXPANDHOPS.expandCrawlerHopPath(hoppathfromcrawler) as hopInfoBag;

OrigUrlsWithHopInfo = FILTER OrigUrlsWithHopInfo BY hopInfoBag is not null;

OrigUrlsWithHopInfo = FOREACH OrigUrlsWithHopInfo GENERATE origurl, FLATTEN(hopInfoBag)
								    as (viaId:chararray, hopPathFromVia:chararray, hopsFromVia:int);

-- add in self link (in case the URL itself has a title in the titles db)
SelfLines = FOREACH OrigUrlsWithCrawlerHopPath GENERATE origurl as origurl:chararray, 
							crawllogid as viaId:chararray, 
							'' as hopPathFromVia:chararray, 
							0 as hopsFromVia:int; 

OrigUrlsWithHopInfo = Union OrigUrlsWithHopInfo, SelfLines;

--Grab all the viaIds. Goal: Find the titles for these vias.
ViaIds = FOREACH OrigUrlsWithHopInfo GENERATE viaId;
ViaIds = DISTINCT ViaIds;

Joined = JOIN ViaIds BY viaId, CrawlLogIdMap BY crawllogid;
ViaIdsUrls = FOREACH Joined GENERATE ViaIds::viaId as viaId, 
				     CrawlLogIdMap::crawllogurl as viaOrigUrl, 
				     SURTURL(CrawlLogIdMap::crawllogurl) as viaUrl;

--join with titles
Joined = JOIN ViaIdsUrls BY viaUrl, UrlTitles BY url;
ViaTitles = FOREACH Joined GENERATE ViaIdsUrls::viaId as viaId, 
				    ViaIdsUrls::viaOrigUrl as viaOrigUrl, 
				    UrlTitles::title as viaTitle;

--join with OrigUrlsWithHopInfo
Joined = Join ViaTitles BY viaId, OrigUrlsWithHopInfo BY viaId;
OrigUrlsWithViaTitles = FOREACH Joined GENERATE OrigUrlsWithHopInfo::origurl as origurl, 
						ViaTitles::viaOrigUrl as viaOrigUrl, 
						ViaTitles::viaTitle as viaTitle,
						OrigUrlsWithHopInfo::hopPathFromVia as hopPathFromVia,
						OrigUrlsWithHopInfo::hopsFromVia as hopsFromVia;

OrigUrlsWithViaTitlesGrp = GROUP OrigUrlsWithViaTitles BY origurl;
OrigUrlsWithClosestViaTitles = FOREACH OrigUrlsWithViaTitlesGrp {
				Closest = ORDER OrigUrlsWithViaTitles BY hopsFromVia;
				Closest = LIMIT Closest 1;
				GENERATE group as origurl, 
					 FLATTEN(Closest.viaOrigUrl) as viaOrigUrl, 
					 FLATTEN(Closest.viaTitle) as viaTitle, 
					 FLATTEN(Closest.hopPathFromVia) as hopPathFromVia, 
					 FLATTEN(Closest.hopsFromVia) as hopsFromVia;
	   		   };

STORE OrigUrlsWithClosestViaTitles into '$O_ORIGURL_CLOSESTVIAORIGURL_CLOSESTVIATITLE_HOPPATHFROMCLOSESTVIA_NUMHOPSROMCLOSESTVIA'; 
