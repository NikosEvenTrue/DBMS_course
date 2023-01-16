BEGIN;

INSERT INTO flash_cards_repeat_system.users(name) VALUES ('nik'), ('roma');
INSERT INTO flash_cards_repeat_system.user_descriptions (user_id) VALUES (1), (2);
INSERT INTO flash_cards_repeat_system.user_credentionals(login, password, user_info_id)
VALUES ('nik', 'kek', 1), ('roma', 'lol', 2);

INSERT INTO flash_cards_repeat_system.folders(name, parent_folder, owner) VALUES
('univercity', NULL, 1), ('unit1', 1, 1), ('exam', 1, 1);

INSERT INTO flash_cards_repeat_system.modules(name, user_id) VALUES
('eng_b1', 1);

INSERT INTO flash_cards_repeat_system.cards(face, back) VALUES
('book', 'книга'), ('cat', 'кот'), ('dog', 'собака');

INSERT INTO flash_cards_repeat_system.cards_users_expirations(next_repeat_at, last_repeated_at, card_id, user_id) VALUES
('2023-01-10 14:52:49'::timestamp, '2023-01-08 14:52:49'::timestamp, 2, 1),
('2023-01-10 14:52:49'::timestamp, '2022-08-20 14:52:49'::timestamp, 1, 1),
('2023-08-20 14:52:49'::timestamp, '2022-08-20 14:52:49'::timestamp, 3, 1);

INSERT INTO flash_cards_repeat_system.cards_modules(card_id, module_id) VALUES
(1, 1), (2, 1), (3, 1);

COMMIT;




EXPLAIN ANALYZE
select * from ready_cards(1, 1);

-- -- по порядку
-- EXPLAIN ANALYZE
SELECT last_repeated_at, cards.id, face, back FROM cards
JOIN cards_users_expirations ON cards.id = cards_users_expirations.card_id
WHERE cards.id IN (
	SELECT card_id FROM cards_users_expirations
	WHERE
		next_repeat_at < now()::timestamp AND
		user_id = 1 AND
		card_id IN (SELECT card_id FROM cards_modules
					WHERE module_id = 1))
ORDER BY last_repeated_at DESC;

