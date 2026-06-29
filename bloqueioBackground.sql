SELECT r1.session_id
,r1.blocking_session_id
,r1.wait_type
,r1.wait_resource
,r1.last_wait_type
,r1.command AS BlockedSessionCommand
,r2.command AS BlockingSessionCommand
,s1.login_name AS BlockedSessionLogin
,s2.login_name AS BlockingSessionLogin
,s1.host_name AS BlockedSessionHost
,s2.host_name AS BlockingSessionHost
,r1.STATUS AS BlockedSessionStatus
,r2.STATUS AS BlockingSessionStatus
FROM sys.dm_exec_requests AS r1
INNER JOIN sys.dm_exec_sessions AS s1 ON r1.session_id = s1.session_id
INNER JOIN sys.dm_exec_sessions AS s2 ON r1.blocking_session_id = s2.session_id
LEFT OUTER JOIN sys.dm_exec_requests AS r2 ON s2.session_id = r2.session_id
WHERE r1.blocking_session_id <> 0
AND r1.STATUS = ‘background’
ORDER BY r1.wait_time DESC;