EXPLAIN ANALYSE
SELECT cards.id, face, back FROM cards
JOIN cards_users_expirations ON cards.id = cards_users_expirations.card_id
WHERE cards.id IN (
	SELECT card_id FROM cards_users_expirations
	WHERE 
		next_repeat_at < now()::timestamp AND
		user_id = 1 AND
		card_id IN (SELECT card_id FROM cards_modules 
					WHERE module_id = 1))
ORDER BY last_repeated_at DESC;

EXPLAIN ANALYSE
SELECT card_id, face, back FROM users_cards
WHERE user_id = 1 AND module_id = 1 AND next_repeat_at < now()::timestamp
ORDER BY last_repeated_at DESC;