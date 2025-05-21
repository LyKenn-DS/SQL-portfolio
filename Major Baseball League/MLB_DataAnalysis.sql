-- PART I: SCHOOL ANALYSIS
SELECT * FROM school_details LIMIT 1000;
SELECT * FROM schools LIMIT 1000;

-- 1. In each decade, how many schools were there that produced MLB players?
SELECT 	CONCAT(FLOOR(yearID / 10) * 10, 's') AS decade,
		COUNT(DISTINCT schoolID) AS num_schools
FROM 	schools
GROUP BY 1
ORDER BY 1;

-- 2. What are the names of the top 5 schools that produced the most players?
SELECT  sd.name_full, COUNT(DISTINCT s.playerID) AS num_players
FROM 	schools s LEFT JOIN school_details sd
	ON s.schoolID = sd.schoolID
GROUP BY 1
ORDER BY 2 DESC
LIMIT 5;

-- 3. For each decade, what were the names of the top 3 schools that produced the most players?
WITH DecadeSchools AS (
	SELECT  CONCAT(FLOOR((s.yearID) / 10) * 10, 's') AS decade,
			sd.name_full,
			COUNT(DISTINCT s.playerID) AS num_players
	FROM 	schools s LEFT JOIN school_details sd
			ON s.schoolID = sd.schoolID
	GROUP BY 1,2
),
	RankedSchools AS (
		SELECT 	decade, name_full, num_players,
				RANK() OVER (PARTITION BY decade ORDER BY num_players DESC) AS school_rank
		FROM DecadeSchools
)

SELECT 	decade, name_full, num_players
FROM RankedSchools
WHERE school_rank <= 3
ORDER BY 1 DESC, 3 DESC;

-- PART II: SALARY ANALYSIS
SELECT * FROM salaries LIMIT 1000;

-- 1. What is the average annual spending for the top 20% of teams?
CREATE TEMPORARY TABLE AnnualTeamSpending AS ( 
	SELECT 	teamID, yearID, SUM(salary) AS annual_spending
	FROM 	salaries
	GROUP BY teamID, yearID
    ORDER BY teamID, yearID
);
	
WITH RankedAvgTS AS (
	SELECT teamID, AVG(annual_spending) AS avg_spend,
	NTILE(5) OVER (ORDER BY AVG(annual_spending) DESC) AS spending_rank
    FROM AnnualTeamSpending
	GROUP BY teamID
)
    
SELECT teamID, ROUND(avg_spend / 1000000, 1) AS avg_spend_millions 
FROM RankedAvgTS
WHERE spending_rank = 1;

-- 2. For each team, show the cumulative suym of spending over the years
SELECT 	*,
		ROUND(SUM(annual_spending) OVER (PARTITION BY teamID ORDER BY yearID) / 1000000, 1)
			AS cumulative_sum
FROM AnnualTeamSpending
ORDER BY teamID;

-- 3. Return the first year that each team's cumulative spending surpassed 1B
WITH cs AS (
	SELECT 	*,
			SUM(annual_spending) OVER (PARTITION BY teamID ORDER BY yearID) AS cumulative_sum
	FROM AnnualTeamSpending
) 
	
SELECT teamID, MIN(yearID) AS yearID, ROUND(MIN(cumulative_sum) / 1000000000, 2) AS cumulative_sum_billions   
FROM cs
WHERE cumulative_sum > 1000000000
GROUP BY 1
ORDER BY 1;

-- PART III: PLAYER CAREER ANALYSIS
SELECT * FROM CleanPlayers LIMIT 1000;

-- 1. Identify if there's any duplicate rows in the data and find the number of players
 SELECT nameFirst, nameLast, nameGiven, birthYear, weight, height, debut FROM players
 GROUP BY 1, 2,3,4,5,6,7
 HAVING COUNT(*) > 1;
 
SELECT COUNT(playerID) FROM players;
 
 -- 2. 	For each player, calculate their age at their first (debut) game, 
 --    	their last game, and their career length (all in years).
 -- 	Sort from longest career to shortest career. 
 CREATE TEMPORARY TABLE CleanPlayers AS (
	SELECT	playerID,
			IF(birthYear IS NULL OR birthMonth IS NULL OR birthDay IS NULL, NULL, 
				CAST(concat_ws('-', birthYear, birthMonth, birthDay) AS DATE)) AS birthdate,
			birthCountry, birthState, birthCity,
			IF(deathYear IS NULL OR deathMonth IS NULL OR deathDay IS NULL, NULL, 
				CAST(concat_ws('-', deathYear, deathMonth, deathDay) AS DATE)) AS deathdate,
			deathCountry, deathState, deathCity,
			nameFirst, nameLast, nameGiven,
			weight, height, bats, throws,
			debut, finalGame, retroID, bbrefID
	 FROM players
 );

SELECT 	nameGiven, 
		timestampdiff(YEAR, birthDate, debut) AS starting_age,
		timestampdiff(YEAR, birthDate, finalGame) AS ending_age,
		timestampdiff(YEAR, debut, finalGame) AS career_length
FROM CleanPlayers
ORDER BY 4 DESC;

-- 3. What team did each player play on for their starting and ending years?
CREATE TEMPORARY TABLE Career AS (
	SELECT 	p.playerID, p.nameGiven,
			YEAR(p.debut) AS starting_year, s.teamID AS starting_team, 
			YEAR(p.finalGame) AS ending_year, e.teamID AS ending_team
	FROM 	CleanPlayers p 	INNER JOIN 	salaries s
										ON p.playerID = s.playerID
										AND YEAR(p.debut) = s.yearID
							INNER JOIN 	salaries e
										ON p.playerID = e.playerID
                                        AND YEAR(p.finalGame) = e.yearID
);

SELECT * FROM Career
ORDER BY 4,3;

-- 4. How many players started and ended on the same team and also played for over a decade
SELECT COUNT(*) AS num_players
FROM Career
WHERE starting_team = ending_team AND (ending_year - starting_year) > 10
ORDER BY starting_team;
 
 -- PART IV: PLAYER COMPARISON ANALYSIS
 SELECT * FROM CleanPlayers LIMIT 1000;
 
 -- 1. Which players have the same birthday?
 SELECT birthDate,
		group_concat(nameGiven ORDER BY nameGiven DESC SEPARATOR ', ') AS player
 FROM CleanPlayers 
 WHERE birthDate IS NOT NULL 
 GROUP BY 1
 HAVING COUNT(playerID) > 1
 ORDER BY 1;
 
 -- 2. Create a summary table that shows for each team, what percent of players
 -- 	bat right, left and both. 
WITH Teams AS (
			SELECT 	DISTINCT p.playerID, s.teamID, p.bats
			FROM 	CleanPlayers p INNER JOIN salaries s
					ON p.playerID = s.playerID
 )
 
 SELECT teamID, 
		AVG(CASE WHEN bats = 'R' THEN 1 ELSE 0 END) AS bats_right,
        AVG(CASE WHEN bats = 'L' THEN 1 ELSE 0 END) AS bats_left,
		AVG(CASE WHEN bats = 'B' THEN 1 ELSE 0 END) AS bats_both
FROM Teams
GROUP BY 1
ORDER BY 1;

 -- 3. How have average height and weight at debut game changed over the years, 
 -- 	and what's the decade-over-decade difference?
WITH Decade_wh AS (
	SELECT	FLOOR(YEAR(debut) / 10) * 10 AS decade, 
			AVG(height) AS avg_h,
            AVG(weight) AS avg_wt
	FROM	CleanPlayers
	WHERE debut IS NOT NULL
	GROUP BY 1
)

SELECT	 *,
		(avg_h - LAG(avg_h) OVER (ORDER BY decade)) AS height_diff,
        (avg_wt - LAG(avg_wt) OVER (ORDER BY decade)) AS weight_diff
FROM Decade_wh;
