.pragma library

// How well `text` matches the query `q` (lower case); higher is better, 0 is no match.
function score(text, q) {
    if (!text) {
        return 0;
    }
    const t = text.toLowerCase();
    if (t === q) return 100;
    if (t.startsWith(q)) return 80;
    if (t.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 60;
    if (t.indexOf(q) !== -1) return 40;
    if (q.length < 3) return 0;
    let i = 0;
    for (const ch of t) {
        if (ch === q[i]) i++;
    }
    return i === q.length ? 15 : 0;
}

// The same keys on the us/ru layouts, so "ешьу" still finds "time" and "сщву" finds "code".
const enKeys = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
const ruKeys = "ёйцукенгшщзхъфывапролджэячсмитьбю";

function swapLayout(q) {
    let out = "";
    for (const ch of q) {
        const i = enKeys.indexOf(ch);
        const j = ruKeys.indexOf(ch);
        out += i !== -1 ? ruKeys[i] : j !== -1 ? enKeys[j] : ch;
    }
    return out;
}

// An entry's match: its name, or its keywords at 0.7.
function entryScore(entry, q) {
    return Math.max(score(entry.name, q), score(entry.keys, q) * 0.7);
}

// The entries matching `query`, best first; `usage` (id -> launches) adds to the score. Without a query: most
// launched first, then by name, without the dangerous and per-theme entries. At most 60.
function results(entries, query, usage) {
    const q = query.trim().toLowerCase();
    const launches = entry => usage[entry.id] || 0;
    let list;
    if (!q) {
        list = entries.filter(entry => !entry.danger && !String(entry.id).startsWith("theme:"))
                      .sort((x, y) => launches(y) - launches(x) || x.name.localeCompare(y.name));
    } else {
        const swapped = swapLayout(q);
        list = entries.map(entry => ({ entry: entry,
                                       score: Math.max(entryScore(entry, q), entryScore(entry, swapped) * 0.9) }))
                      .filter(found => found.score > 0)
                      .map(found => ({ entry: found.entry, score: found.score + Math.log(1 + launches(found.entry)) * 6 }))
                      .sort((x, y) => y.score - x.score)
                      .map(found => found.entry);
    }
    return list.slice(0, 60);
}
