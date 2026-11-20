.pragma library

// Brings a ListModel to `rows` (plain objects, all with the same roles) in place, matching rows by
// the role named `key`. A row that stays keeps its delegate, and the delegate its state (the scroll
// position, an open card, text typed into it); it only gets its new values. New rows are inserted,
// gone ones removed, reordered ones moved. Assigning a new array to `model:` would instead destroy
// and recreate every delegate on each refresh.
function sync(model, rows, key) {
    const wanted = new Set(rows.map(row => row[key]));
    for (let i = model.count - 1; i >= 0; i--) {
        if (!wanted.has(model.get(i)[key])) {
            model.remove(i);
        }
    }
    for (let i = 0; i < rows.length; i++) {
        let j = i;
        while (j < model.count && model.get(j)[key] !== rows[i][key]) {
            j++;
        }
        if (j === model.count) {
            model.insert(i, rows[i]);
            continue;
        }
        if (j !== i) {
            model.move(j, i, 1);
        }
        model.set(i, rows[i]);
    }
}
