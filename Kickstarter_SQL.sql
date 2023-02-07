-- nulls check
select count(*) from campaign where sub_category_id is null;
select count(*) from campaign where country_id is null;
select count(*) from campaign where currency_id is null;

-- bad joins check (should return one row)
select count(*) from campaign cg 
join country co on cg.country_id = co.id
join sub_category sc on cg.sub_category_id = sc.id
join category ca on sc.category_id = ca.id
union
select count(*) from campaign;

-- weird country
select distinct name, id from country;
select * from campaign where country_id = 11;

-- outlier removal. I will do this by hand because MySQL doesn't seem to have percentile functions, which is annoying.
select round(pledged,0) from campaign order by 1 desc; -- looks okay

select round(goal,0) from campaign order by 1 desc; -- some very large ones there; let's dump everything >= 10^8
select count(*) from campaign where goal >= power(10,8); -- 5 records

select round(backers,0) from campaign order by 1 desc; -- remove the one super huge one
select count(*) from campaign where backers >= power(10,5); -- 1 record

drop table campaign_clean;
create table campaign_clean as
select * from campaign
where not (
	goal >= power(10,8)
    or backers >= power(10,5)
)
;

-- looks good - difference of six
select count(*) from campaign_clean
union select count(*) from campaign
;

-- put all this in a nice view
create or replace view joined as
select
	cg.name name,
    launched,
    deadline,
    goal,
    pledged,
    backers,
    outcome,
    co.name country,
    co.id country_id,
    ca.name category,
    ca.id category_id,
    sc.name subcategory,
    sc.id subcategory_id,
    cu.name currency,
    cu.id currency_id
from campaign_clean cg
join country co on cg.country_id = co.id
join sub_category sc on cg.sub_category_id = sc.id
join category ca on sc.category_id = ca.id
join currency cu on cu.id = cg.currency_id
;

select * from joined;

-- # of rows
select count(*) from campaign_clean;

-- time range
select min(launched),  max(launched) from campaign_clean;

-- duplicated companies
select sub_category_id, name, count(*) from campaign_clean group by 1, 2 having count(*) > 1;

-- outcomes
select outcome, count(*) perc from campaign_clean group by 1 order by 2;

-- currency issue
select
	currency_id,
    cu.name,
    round(avg(goal)) goal
from campaign cp
join currency cu on cu.id = cp.currency_id
group by 1, 2
order by 3
;

-- Are the goals for dollars raised significantly different between campaigns that are successful and unsuccessful?
select 
	if(outcome = 'successful', 1, 0) is_successful,
	if(country = 'US', 1, 0) is_USA,
	-- if(ca.id = 7, 1, 0) is_boardgame,
    round(avg(goal),2) goal
from joined
group by 1,2 with rollup
order by 1,2
;

-- What are the top/bottom 3 categories with the most backers? 
select 
	if(country = 'US', 1, 0) is_USA,
    category category_name,
    round(sum(backers),2) backers
from joined
group by 2,1 with rollup
order by 1,3,2
;

-- What are the top/bottom 3 subcategories by backers?
select 
	if(country  = 'US', 1, 0) is_USA,
    subcategory,
    round(sum(backers),2) backers
from joined
where category_id = 7
group by 2,1 with rollup
order by 1,3,2
;

-- What are the top/bottom 3 categories with the biggest pledges?
select 
    category,
    round(sum(pledged),2) pledged
from joined
group by 1
order by 2 desc
;

-- What are the top/bottom 3 subcategories by backers?
select 
    subcategory,
    round(sum(pledged),2) pledged
from joined
where category_id = 7
group by 1
order by 2 desc
;

-- What was the amount the most successful board game company raised? How many backers did they have?
select * from joined where outcome = 'successful' order by pledged desc;
select * from joined where outcome = 'successful' order by backers desc;
select * from joined where outcome = 'successful' and subcategory_id = 14 order by pledged desc;
select * from joined where outcome = 'successful' and subcategory_id = 14 order by backers desc;

-- Rank the top three countries with the most successful campaigns in terms of dollars (total amount pledged)
select
	country,
    avg(pledged) pledged
from joined
group by 1
order by 2 desc
limit 3
;

-- Rank the top three countries with the number of campaigns backed.
select
	country,
    count(*) num_campaigns
from joined
group by 1
order by 2 desc
limit 3
;

-- doing medians rather than means for recommendations because of outliers

-- What is a realistic Kickstarter campaign goal (in dollars) should the company aim to raise?
create table goals as
select goal 
from joined
where 
	subcategory_id = 14
    and country_id = 2
    and outcome = 'successful'
order by 1
;

-- fun way of finding median in mysql
SELECT x.goal from goals x, goals y
GROUP BY x.goal
HAVING SUM(SIGN(1-SIGN(y.goal - x.goal)))/COUNT(*) > .5
LIMIT 1
;

-- How many backers will be needed to meet their goal?
create table backers1 as
select backers 
from joined
where 
	subcategory_id = 14
    and country_id = 2
    and outcome = 'successful'
order by 1
;

SELECT x.backers from backers1 x, backers1 y
GROUP BY x.backers
HAVING SUM(SIGN(1-SIGN(y.backers- x.backers)))/COUNT(*) > .5
LIMIT 1
;

-- How many backers can the company realistically expect, based on trends in their category?
create table backers2 as
select backers 
from joined
where 
	subcategory_id = 14
    and country_id = 2
order by 1
;

SELECT x.backers from backers2 x, backers2 y
GROUP BY x.backers
HAVING SUM(SIGN(1-SIGN(y.backers- x.backers)))/COUNT(*) > .5
LIMIT 1
;

