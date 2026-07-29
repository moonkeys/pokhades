#!/bin/bash
# Smoke-tests Pokhades — à lancer AVANT chaque build/commit.
# Usage : tests/smoke.sh [chemin/vers/Godot]
# Vérifie : boot sans erreur de script, run solo (salle 0 et acte avancé),
# et une partie multijoueur hôte+client complète. Code de sortie != 0 si
# un scénario échoue ou si une erreur de script apparaît.

set -u
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAIL=0

cleanup() { pkill -9 -f "Godot --headless --path $PROJ" 2>/dev/null; }
trap cleanup EXIT

run_scenario() {  # nom, timeout, args...
	local name="$1"; local timeout_s="$2"; shift 2
	local log="$TMP/$name.log"
	"$GODOT" --headless --path "$PROJ" -- "$@" > "$log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 $pid 2>/dev/null && [ $waited -lt "$timeout_s" ]; do
		sleep 1; waited=$((waited+1))
	done
	kill -9 $pid 2>/dev/null
	if grep -q "SCRIPT ERROR\|Parse Error" "$log"; then
		echo "✗ $name — erreur de script :"
		grep -m3 "SCRIPT ERROR\|Parse Error" "$log" | sed 's/^/    /'
		FAIL=1
	elif grep -q "SMOKE_FAIL" "$log"; then
		echo "✗ $name — $(grep -m1 SMOKE_FAIL "$log")"
		FAIL=1
	elif grep -q "SMOKE_OK" "$log"; then
		echo "✓ $name — $(grep -m1 SMOKE_OK "$log" | cut -d' ' -f3-)"
	else
		echo "✗ $name — aucun marqueur (crash/timeout ?), fin du log :"
		tail -3 "$log" | sed 's/^/    /'
		FAIL=1
	fi
}

echo "── Smoke-tests Pokhades ──"

run_scenario boot        20 smoke_boot
run_scenario hub         25 smoke_hub
run_scenario story       20 smoke_story
run_scenario rumors      20 smoke_rumors
run_scenario recruit     20 smoke_recruit
run_scenario final_boss  20 smoke_final_boss
run_scenario npc_dialogue 20 smoke_npc_dialogue
run_scenario boutique_dialogue 25 smoke_boutique_dialogue
run_scenario freed_pokemon 20 smoke_freed_pokemon
run_scenario boon_claim  20 smoke_boon_claim
run_scenario xp_share    20 smoke_xp_share
run_scenario lobby_item_stats 20 smoke_lobby_item_stats
run_scenario cooldown_focus 20 smoke_cooldown_focus
run_scenario new_bonuses 25 smoke_new_bonuses
run_scenario team_buff  20 smoke_team_buff
run_scenario move_upgrade 20 smoke_move_upgrade
run_scenario los_throttle 20 smoke_los_throttle
run_scenario sprite_occlusion 20 smoke_sprite_occlusion
run_scenario portrait_race 20 smoke_portrait_race
run_scenario stats_overlay_item 20 smoke_stats_overlay_item
run_scenario enemy_aggro 20 smoke_enemy_aggro
run_scenario auto_revive 20 smoke_auto_revive
run_scenario pokedex     20 smoke_pokedex
run_scenario pokedex_revive 20 smoke_pokedex_revive
run_scenario pokedex_stress 30 smoke_pokedex_stress
run_scenario run_solo    25 smoke_run
run_scenario run_acte2   25 smoke_run_room=9
run_scenario run_boss    30 smoke_run_room=6

# Multijoueur : l'hôte d'abord (en fond), on récupère son code, le client rejoint.
HOST_LOG="$TMP/mp_host.log"
"$GODOT" --headless --path "$PROJ" -- mp_test_host > "$HOST_LOG" 2>&1 &
HOST_PID=$!
CODE=""
for i in $(seq 1 15); do
	CODE=$(grep -m1 "SMOKE_CODE=" "$HOST_LOG" 2>/dev/null | cut -d= -f2)
	[ -n "$CODE" ] && break
	sleep 1
done
if [ -z "$CODE" ]; then
	echo "✗ mp_host — pas de code de partie (port occupé ?)"
	kill -9 $HOST_PID 2>/dev/null
	FAIL=1
else
	run_scenario mp_join 40 "mp_test_join=$CODE"
	waited=0
	while kill -0 $HOST_PID 2>/dev/null && [ $waited -lt 45 ]; do sleep 1; waited=$((waited+1)); done
	kill -9 $HOST_PID 2>/dev/null
	if grep -q "SMOKE_OK mp_host" "$HOST_LOG"; then
		echo "✓ mp_host — $(grep -m1 'SMOKE_OK mp_host' "$HOST_LOG" | cut -d' ' -f3-)"
	else
		echo "✗ mp_host — $(grep -m1 'SMOKE_FAIL' "$HOST_LOG" || echo 'aucun marqueur')"
		FAIL=1
	fi
fi

rm -rf "$TMP"
if [ $FAIL -ne 0 ]; then
	echo "── ÉCHEC ──"; exit 1
fi
echo "── Tous les smoke-tests passent ──"
