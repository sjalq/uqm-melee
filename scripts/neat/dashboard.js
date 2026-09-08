(function(scope){
'use strict';

function F(arity, fun, wrapper) {
  wrapper.a = arity;
  wrapper.f = fun;
  return wrapper;
}

function F2(fun) {
  return F(2, fun, function(a) { return function(b) { return fun(a,b); }; })
}
function F3(fun) {
  return F(3, fun, function(a) {
    return function(b) { return function(c) { return fun(a, b, c); }; };
  });
}
function F4(fun) {
  return F(4, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return fun(a, b, c, d); }; }; };
  });
}
function F5(fun) {
  return F(5, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return fun(a, b, c, d, e); }; }; }; };
  });
}
function F6(fun) {
  return F(6, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return fun(a, b, c, d, e, f); }; }; }; }; };
  });
}
function F7(fun) {
  return F(7, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return fun(a, b, c, d, e, f, g); }; }; }; }; }; };
  });
}
function F8(fun) {
  return F(8, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) {
    return fun(a, b, c, d, e, f, g, h); }; }; }; }; }; }; };
  });
}
function F9(fun) {
  return F(9, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) { return function(i) {
    return fun(a, b, c, d, e, f, g, h, i); }; }; }; }; }; }; }; };
  });
}

function A2(fun, a, b) {
  return fun.a === 2 ? fun.f(a, b) : fun(a)(b);
}
function A3(fun, a, b, c) {
  return fun.a === 3 ? fun.f(a, b, c) : fun(a)(b)(c);
}
function A4(fun, a, b, c, d) {
  return fun.a === 4 ? fun.f(a, b, c, d) : fun(a)(b)(c)(d);
}
function A5(fun, a, b, c, d, e) {
  return fun.a === 5 ? fun.f(a, b, c, d, e) : fun(a)(b)(c)(d)(e);
}
function A6(fun, a, b, c, d, e, f) {
  return fun.a === 6 ? fun.f(a, b, c, d, e, f) : fun(a)(b)(c)(d)(e)(f);
}
function A7(fun, a, b, c, d, e, f, g) {
  return fun.a === 7 ? fun.f(a, b, c, d, e, f, g) : fun(a)(b)(c)(d)(e)(f)(g);
}
function A8(fun, a, b, c, d, e, f, g, h) {
  return fun.a === 8 ? fun.f(a, b, c, d, e, f, g, h) : fun(a)(b)(c)(d)(e)(f)(g)(h);
}
function A9(fun, a, b, c, d, e, f, g, h, i) {
  return fun.a === 9 ? fun.f(a, b, c, d, e, f, g, h, i) : fun(a)(b)(c)(d)(e)(f)(g)(h)(i);
}




var _JsArray_empty = [];

function _JsArray_singleton(value)
{
    return [value];
}

function _JsArray_length(array)
{
    return array.length;
}

var _JsArray_initialize = F3(function(size, offset, func)
{
    var result = new Array(size);

    for (var i = 0; i < size; i++)
    {
        result[i] = func(offset + i);
    }

    return result;
});

var _JsArray_initializeFromList = F2(function (max, ls)
{
    var result = new Array(max);

    for (var i = 0; i < max && ls.b; i++)
    {
        result[i] = ls.a;
        ls = ls.b;
    }

    result.length = i;
    return _Utils_Tuple2(result, ls);
});

var _JsArray_unsafeGet = F2(function(index, array)
{
    return array[index];
});

var _JsArray_unsafeSet = F3(function(index, value, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[index] = value;
    return result;
});

var _JsArray_push = F2(function(value, array)
{
    var length = array.length;
    var result = new Array(length + 1);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[length] = value;
    return result;
});

var _JsArray_foldl = F3(function(func, acc, array)
{
    var length = array.length;

    for (var i = 0; i < length; i++)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_foldr = F3(function(func, acc, array)
{
    for (var i = array.length - 1; i >= 0; i--)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_map = F2(function(func, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = func(array[i]);
    }

    return result;
});

var _JsArray_indexedMap = F3(function(func, offset, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = A2(func, offset + i, array[i]);
    }

    return result;
});

var _JsArray_slice = F3(function(from, to, array)
{
    return array.slice(from, to);
});

var _JsArray_appendN = F3(function(n, dest, source)
{
    var destLen = dest.length;
    var itemsToCopy = n - destLen;

    if (itemsToCopy > source.length)
    {
        itemsToCopy = source.length;
    }

    var size = destLen + itemsToCopy;
    var result = new Array(size);

    for (var i = 0; i < destLen; i++)
    {
        result[i] = dest[i];
    }

    for (var i = 0; i < itemsToCopy; i++)
    {
        result[i + destLen] = source[i];
    }

    return result;
});



// LOG

var _Debug_log_UNUSED = F2(function(tag, value)
{
	return value;
});

var _Debug_log = F2(function(tag, value)
{
	console.log(tag + ': ' + _Debug_toString(value));
	return value;
});


// TODOS

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}


// TO STRING

function _Debug_toString_UNUSED(value)
{
	return '<internals>';
}

function _Debug_toString(value)
{
	return _Debug_toAnsiString(false, value);
}

function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}


// CRASH


function _Debug_crash_UNUSED(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash(identifier, fact1, fact2, fact3, fact4)
{
	switch(identifier)
	{
		case 0:
			throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

		case 1:
			throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

		case 2:
			var jsonErrorString = fact1;
			throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

		case 3:
			var portName = fact1;
			throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

		case 4:
			var portName = fact1;
			var problem = fact2;
			throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

		case 5:
			throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

		case 6:
			var moduleName = fact1;
			throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

		case 8:
			var moduleName = fact1;
			var region = fact2;
			var message = fact3;
			throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

		case 9:
			var moduleName = fact1;
			var region = fact2;
			var value = fact3;
			var message = fact4;
			throw new Error(
				'TODO in module `' + moduleName + '` from the `case` expression '
				+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
				+ _Debug_toString(value).replace('\n', '\n    ')
				+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
			);

		case 10:
			throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

		case 11:
			throw new Error('Cannot perform mod 0. Division by zero error.');
	}
}

function _Debug_regionToString(region)
{
	if (region.start.line === region.end.line)
	{
		return 'on line ' + region.start.line;
	}
	return 'on lines ' + region.start.line + ' through ' + region.end.line;
}



// EQUALITY

function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**_UNUSED/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	/**/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**_UNUSED/
	if (typeof x.$ === 'undefined')
	//*/
	/**/
	if (x.$[0] === '#')
	//*/
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});


// COMMON VALUES

var _Utils_Tuple0_UNUSED = 0;
var _Utils_Tuple0 = { $: '#0' };

function _Utils_Tuple2_UNUSED(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3_UNUSED(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr_UNUSED(c) { return c; }
function _Utils_chr(c) { return new String(c); }


// RECORDS

function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

var _Utils_append = F2(_Utils_ap);

function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}



var _List_Nil_UNUSED = { $: 0 };
var _List_Nil = { $: '[]' };

function _List_Cons_UNUSED(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons(hd, tl) { return { $: '::', a: hd, b: tl }; }


var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}

var _List_map2 = F3(function(f, xs, ys)
{
	for (var arr = []; xs.b && ys.b; xs = xs.b, ys = ys.b) // WHILE_CONSES
	{
		arr.push(A2(f, xs.a, ys.a));
	}
	return _List_fromArray(arr);
});

var _List_map3 = F4(function(f, xs, ys, zs)
{
	for (var arr = []; xs.b && ys.b && zs.b; xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A3(f, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map4 = F5(function(f, ws, xs, ys, zs)
{
	for (var arr = []; ws.b && xs.b && ys.b && zs.b; ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A4(f, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map5 = F6(function(f, vs, ws, xs, ys, zs)
{
	for (var arr = []; vs.b && ws.b && xs.b && ys.b && zs.b; vs = vs.b, ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A5(f, vs.a, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_sortBy = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		return _Utils_cmp(f(a), f(b));
	}));
});

var _List_sortWith = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		var ord = A2(f, a, b);
		return ord === $elm$core$Basics$EQ ? 0 : ord === $elm$core$Basics$LT ? -1 : 1;
	}));
});



// MATH

var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

// https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/divmodnote-letter.pdf
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});


// TRIGONOMETRY

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);


// MORE MATH

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;


// BOOLEANS

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });



var _String_cons = F2(function(chr, str)
{
	return chr + str;
});

function _String_uncons(string)
{
	var word = string.charCodeAt(0);
	return !isNaN(word)
		? $elm$core$Maybe$Just(
			0xD800 <= word && word <= 0xDBFF
				? _Utils_Tuple2(_Utils_chr(string[0] + string[1]), string.slice(2))
				: _Utils_Tuple2(_Utils_chr(string[0]), string.slice(1))
		)
		: $elm$core$Maybe$Nothing;
}

var _String_append = F2(function(a, b)
{
	return a + b;
});

function _String_length(str)
{
	return str.length;
}

var _String_map = F2(function(func, string)
{
	var len = string.length;
	var array = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = string.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			array[i] = func(_Utils_chr(string[i] + string[i+1]));
			i += 2;
			continue;
		}
		array[i] = func(_Utils_chr(string[i]));
		i++;
	}
	return array.join('');
});

var _String_filter = F2(function(isGood, str)
{
	var arr = [];
	var len = str.length;
	var i = 0;
	while (i < len)
	{
		var char = str[i];
		var word = str.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += str[i];
			i++;
		}

		if (isGood(_Utils_chr(char)))
		{
			arr.push(char);
		}
	}
	return arr.join('');
});

function _String_reverse(str)
{
	var len = str.length;
	var arr = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = str.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			arr[len - i] = str[i + 1];
			i++;
			arr[len - i] = str[i - 1];
			i++;
		}
		else
		{
			arr[len - i] = str[i];
			i++;
		}
	}
	return arr.join('');
}

var _String_foldl = F3(function(func, state, string)
{
	var len = string.length;
	var i = 0;
	while (i < len)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += string[i];
			i++;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_foldr = F3(function(func, state, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_split = F2(function(sep, str)
{
	return str.split(sep);
});

var _String_join = F2(function(sep, strs)
{
	return strs.join(sep);
});

var _String_slice = F3(function(start, end, str) {
	return str.slice(start, end);
});

function _String_trim(str)
{
	return str.trim();
}

function _String_trimLeft(str)
{
	return str.replace(/^\s+/, '');
}

function _String_trimRight(str)
{
	return str.replace(/\s+$/, '');
}

function _String_words(str)
{
	return _List_fromArray(str.trim().split(/\s+/g));
}

function _String_lines(str)
{
	return _List_fromArray(str.split(/\r\n|\r|\n/g));
}

function _String_toUpper(str)
{
	return str.toUpperCase();
}

function _String_toLower(str)
{
	return str.toLowerCase();
}

var _String_any = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (isGood(_Utils_chr(char)))
		{
			return true;
		}
	}
	return false;
});

var _String_all = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (!isGood(_Utils_chr(char)))
		{
			return false;
		}
	}
	return true;
});

var _String_contains = F2(function(sub, str)
{
	return str.indexOf(sub) > -1;
});

var _String_startsWith = F2(function(sub, str)
{
	return str.indexOf(sub) === 0;
});

var _String_endsWith = F2(function(sub, str)
{
	return str.length >= sub.length &&
		str.lastIndexOf(sub) === str.length - sub.length;
});

var _String_indexes = F2(function(sub, str)
{
	var subLen = sub.length;

	if (subLen < 1)
	{
		return _List_Nil;
	}

	var i = 0;
	var is = [];

	while ((i = str.indexOf(sub, i)) > -1)
	{
		is.push(i);
		i = i + subLen;
	}

	return _List_fromArray(is);
});


// TO STRING

function _String_fromNumber(number)
{
	return number + '';
}


// INT CONVERSIONS

function _String_toInt(str)
{
	var total = 0;
	var code0 = str.charCodeAt(0);
	var start = code0 == 0x2B /* + */ || code0 == 0x2D /* - */ ? 1 : 0;

	for (var i = start; i < str.length; ++i)
	{
		var code = str.charCodeAt(i);
		if (code < 0x30 || 0x39 < code)
		{
			return $elm$core$Maybe$Nothing;
		}
		total = 10 * total + code - 0x30;
	}

	return i == start
		? $elm$core$Maybe$Nothing
		: $elm$core$Maybe$Just(code0 == 0x2D ? -total : total);
}


// FLOAT CONVERSIONS

function _String_toFloat(s)
{
	// check if it is a hex, octal, or binary number
	if (s.length === 0 || /[\sxbo]/.test(s))
	{
		return $elm$core$Maybe$Nothing;
	}
	var n = +s;
	// faster isNaN check
	return n === n ? $elm$core$Maybe$Just(n) : $elm$core$Maybe$Nothing;
}

function _String_fromList(chars)
{
	return _List_toArray(chars).join('');
}




function _Char_toCode(char)
{
	var code = char.charCodeAt(0);
	if (0xD800 <= code && code <= 0xDBFF)
	{
		return (code - 0xD800) * 0x400 + char.charCodeAt(1) - 0xDC00 + 0x10000
	}
	return code;
}

function _Char_fromCode(code)
{
	return _Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '\uFFFD'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}

function _Char_toUpper(char)
{
	return _Utils_chr(char.toUpperCase());
}

function _Char_toLower(char)
{
	return _Utils_chr(char.toLowerCase());
}

function _Char_toLocaleUpper(char)
{
	return _Utils_chr(char.toLocaleUpperCase());
}

function _Char_toLocaleLower(char)
{
	return _Utils_chr(char.toLocaleLowerCase());
}



/**/
function _Json_errorToString(error)
{
	return $elm$json$Json$Decode$errorToString(error);
}
//*/


// CORE DECODERS

function _Json_succeed(msg)
{
	return {
		$: 0,
		a: msg
	};
}

function _Json_fail(msg)
{
	return {
		$: 1,
		a: msg
	};
}

function _Json_decodePrim(decoder)
{
	return { $: 2, b: decoder };
}

var _Json_decodeInt = _Json_decodePrim(function(value) {
	return (typeof value !== 'number')
		? _Json_expecting('an INT', value)
		:
	(-2147483647 < value && value < 2147483647 && (value | 0) === value)
		? $elm$core$Result$Ok(value)
		:
	(isFinite(value) && !(value % 1))
		? $elm$core$Result$Ok(value)
		: _Json_expecting('an INT', value);
});

var _Json_decodeBool = _Json_decodePrim(function(value) {
	return (typeof value === 'boolean')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a BOOL', value);
});

var _Json_decodeFloat = _Json_decodePrim(function(value) {
	return (typeof value === 'number')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FLOAT', value);
});

var _Json_decodeValue = _Json_decodePrim(function(value) {
	return $elm$core$Result$Ok(_Json_wrap(value));
});

var _Json_decodeString = _Json_decodePrim(function(value) {
	return (typeof value === 'string')
		? $elm$core$Result$Ok(value)
		: (value instanceof String)
			? $elm$core$Result$Ok(value + '')
			: _Json_expecting('a STRING', value);
});

function _Json_decodeList(decoder) { return { $: 3, b: decoder }; }
function _Json_decodeArray(decoder) { return { $: 4, b: decoder }; }

function _Json_decodeNull(value) { return { $: 5, c: value }; }

var _Json_decodeField = F2(function(field, decoder)
{
	return {
		$: 6,
		d: field,
		b: decoder
	};
});

var _Json_decodeIndex = F2(function(index, decoder)
{
	return {
		$: 7,
		e: index,
		b: decoder
	};
});

function _Json_decodeKeyValuePairs(decoder)
{
	return {
		$: 8,
		b: decoder
	};
}

function _Json_mapMany(f, decoders)
{
	return {
		$: 9,
		f: f,
		g: decoders
	};
}

var _Json_andThen = F2(function(callback, decoder)
{
	return {
		$: 10,
		b: decoder,
		h: callback
	};
});

function _Json_oneOf(decoders)
{
	return {
		$: 11,
		g: decoders
	};
}


// DECODING OBJECTS

var _Json_map1 = F2(function(f, d1)
{
	return _Json_mapMany(f, [d1]);
});

var _Json_map2 = F3(function(f, d1, d2)
{
	return _Json_mapMany(f, [d1, d2]);
});

var _Json_map3 = F4(function(f, d1, d2, d3)
{
	return _Json_mapMany(f, [d1, d2, d3]);
});

var _Json_map4 = F5(function(f, d1, d2, d3, d4)
{
	return _Json_mapMany(f, [d1, d2, d3, d4]);
});

var _Json_map5 = F6(function(f, d1, d2, d3, d4, d5)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5]);
});

var _Json_map6 = F7(function(f, d1, d2, d3, d4, d5, d6)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6]);
});

var _Json_map7 = F8(function(f, d1, d2, d3, d4, d5, d6, d7)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7]);
});

var _Json_map8 = F9(function(f, d1, d2, d3, d4, d5, d6, d7, d8)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7, d8]);
});


// DECODE

var _Json_runOnString = F2(function(decoder, string)
{
	try
	{
		var value = JSON.parse(string);
		return _Json_runHelp(decoder, value);
	}
	catch (e)
	{
		return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'This is not valid JSON! ' + e.message, _Json_wrap(string)));
	}
});

var _Json_run = F2(function(decoder, value)
{
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

function _Json_runHelp(decoder, value)
{
	switch (decoder.$)
	{
		case 2:
			return decoder.b(value);

		case 5:
			return (value === null)
				? $elm$core$Result$Ok(decoder.c)
				: _Json_expecting('null', value);

		case 3:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('a LIST', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _List_fromArray);

		case 4:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _Json_toElmArray);

		case 6:
			var field = decoder.d;
			if (typeof value !== 'object' || value === null || !(field in value))
			{
				return _Json_expecting('an OBJECT with a field named `' + field + '`', value);
			}
			var result = _Json_runHelp(decoder.b, value[field]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, field, result.a));

		case 7:
			var index = decoder.e;
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			if (index >= value.length)
			{
				return _Json_expecting('a LONGER array. Need index ' + index + ' but only see ' + value.length + ' entries', value);
			}
			var result = _Json_runHelp(decoder.b, value[index]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, index, result.a));

		case 8:
			if (typeof value !== 'object' || value === null || _Json_isArray(value))
			{
				return _Json_expecting('an OBJECT', value);
			}

			var keyValuePairs = _List_Nil;
			// TODO test perf of Object.keys and switch when support is good enough
			for (var key in value)
			{
				if (value.hasOwnProperty(key))
				{
					var result = _Json_runHelp(decoder.b, value[key]);
					if (!$elm$core$Result$isOk(result))
					{
						return $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, key, result.a));
					}
					keyValuePairs = _List_Cons(_Utils_Tuple2(key, result.a), keyValuePairs);
				}
			}
			return $elm$core$Result$Ok($elm$core$List$reverse(keyValuePairs));

		case 9:
			var answer = decoder.f;
			var decoders = decoder.g;
			for (var i = 0; i < decoders.length; i++)
			{
				var result = _Json_runHelp(decoders[i], value);
				if (!$elm$core$Result$isOk(result))
				{
					return result;
				}
				answer = answer(result.a);
			}
			return $elm$core$Result$Ok(answer);

		case 10:
			var result = _Json_runHelp(decoder.b, value);
			return (!$elm$core$Result$isOk(result))
				? result
				: _Json_runHelp(decoder.h(result.a), value);

		case 11:
			var errors = _List_Nil;
			for (var temp = decoder.g; temp.b; temp = temp.b) // WHILE_CONS
			{
				var result = _Json_runHelp(temp.a, value);
				if ($elm$core$Result$isOk(result))
				{
					return result;
				}
				errors = _List_Cons(result.a, errors);
			}
			return $elm$core$Result$Err($elm$json$Json$Decode$OneOf($elm$core$List$reverse(errors)));

		case 1:
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, decoder.a, _Json_wrap(value)));

		case 0:
			return $elm$core$Result$Ok(decoder.a);
	}
}

function _Json_runArrayDecoder(decoder, value, toElmValue)
{
	var len = value.length;
	var array = new Array(len);
	for (var i = 0; i < len; i++)
	{
		var result = _Json_runHelp(decoder, value[i]);
		if (!$elm$core$Result$isOk(result))
		{
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, i, result.a));
		}
		array[i] = result.a;
	}
	return $elm$core$Result$Ok(toElmValue(array));
}

function _Json_isArray(value)
{
	return Array.isArray(value) || (typeof FileList !== 'undefined' && value instanceof FileList);
}

function _Json_toElmArray(array)
{
	return A2($elm$core$Array$initialize, array.length, function(i) { return array[i]; });
}

function _Json_expecting(type, value)
{
	return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'Expecting ' + type, _Json_wrap(value)));
}


// EQUALITY

function _Json_equality(x, y)
{
	if (x === y)
	{
		return true;
	}

	if (x.$ !== y.$)
	{
		return false;
	}

	switch (x.$)
	{
		case 0:
		case 1:
			return x.a === y.a;

		case 2:
			return x.b === y.b;

		case 5:
			return x.c === y.c;

		case 3:
		case 4:
		case 8:
			return _Json_equality(x.b, y.b);

		case 6:
			return x.d === y.d && _Json_equality(x.b, y.b);

		case 7:
			return x.e === y.e && _Json_equality(x.b, y.b);

		case 9:
			return x.f === y.f && _Json_listEquality(x.g, y.g);

		case 10:
			return x.h === y.h && _Json_equality(x.b, y.b);

		case 11:
			return _Json_listEquality(x.g, y.g);
	}
}

function _Json_listEquality(aDecoders, bDecoders)
{
	var len = aDecoders.length;
	if (len !== bDecoders.length)
	{
		return false;
	}
	for (var i = 0; i < len; i++)
	{
		if (!_Json_equality(aDecoders[i], bDecoders[i]))
		{
			return false;
		}
	}
	return true;
}


// ENCODE

var _Json_encode = F2(function(indentLevel, value)
{
	return JSON.stringify(_Json_unwrap(value), null, indentLevel) + '';
});

function _Json_wrap(value) { return { $: 0, a: value }; }
function _Json_unwrap(value) { return value.a; }

function _Json_wrap_UNUSED(value) { return value; }
function _Json_unwrap_UNUSED(value) { return value; }

function _Json_emptyArray() { return []; }
function _Json_emptyObject() { return {}; }

var _Json_addField = F3(function(key, value, object)
{
	object[key] = _Json_unwrap(value);
	return object;
});

function _Json_addEntry(func)
{
	return F2(function(entry, array)
	{
		array.push(_Json_unwrap(func(entry)));
		return array;
	});
}

var _Json_encodeNull = _Json_wrap(null);



// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: 0,
		a: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: 1,
		a: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: 2,
		b: callback,
		c: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: 3,
		b: callback,
		d: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: 4,
		b: callback,
		d: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: 5,
		b: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		e: _Scheduler_guid++,
		f: task,
		g: null,
		h: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.h.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.f;
		if (task.$ === 2 && task.c)
		{
			task.c();
		}

		proc.f = null;

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


function _Scheduler_step(proc)
{
	while (proc.f)
	{
		var rootTag = proc.f.$;
		if (rootTag === 0 || rootTag === 1)
		{
			while (proc.g && proc.g.$ !== rootTag)
			{
				proc.g = proc.g.i;
			}
			if (!proc.g)
			{
				return;
			}
			proc.f = proc.g.b(proc.f.a);
			proc.g = proc.g.i;
		}
		else if (rootTag === 2)
		{
			proc.f.c = proc.f.b(function(newRoot) {
				proc.f = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === 5)
		{
			if (proc.h.length === 0)
			{
				return;
			}
			proc.f = proc.f.b(proc.h.shift());
		}
		else // if (rootTag === 3 || rootTag === 4)
		{
			proc.g = {
				$: rootTag === 3 ? 0 : 1,
				b: proc.f.b,
				i: proc.g
			};
			proc.f = proc.f.d;
		}
	}
}



function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}




// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.init,
		impl.update,
		impl.subscriptions,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**/, _Json_errorToString(result.a) /**/);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS
//
// This is used by code in elm/browser and elm/http
// to register any HTTP requests that are triggered by init.
//


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.a)
		{
			ports = ports || {};
			ports[key] = manager.a(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		b: init,
		c: onEffects,
		d: onSelfMsg,
		e: cmdMap,
		f: subMap
	};
}


function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		g: sendToApp,
		h: undefined
	};

	var onEffects = info.c;
	var onSelfMsg = info.d;
	var cmdMap = info.e;
	var subMap = info.f;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === 0)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.i, value.j, state)
				: A3(onEffects, router, cmdMap ? value.i : value.j, state);
		}));
	}

	return router.h = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.b));
}



// ROUTING


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.g(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.h, {
		$: 0,
		a: msg
	});
});



// BAGS


function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: 1,
			k: home,
			l: value
		};
	};
}


function _Platform_batch(list)
{
	return {
		$: 2,
		m: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: 3,
		n: tagger,
		o: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS
//
// Effects must be queued!
//
// Say your init contains a synchronous command, like Time.now or Time.here
//
//   - This will produce a batch of effects (FX_1)
//   - The synchronous task triggers the subsequent `update` call
//   - This will produce a batch of effects (FX_2)
//
// If we just start dispatching FX_2, subscriptions from FX_2 can be processed
// before subscriptions from FX_1. No good! Earlier versions of this code had
// this problem, leading to these reports:
//
//   https://github.com/elm/core/issues/980
//   https://github.com/elm/core/pull/981
//   https://github.com/elm/compiler/issues/1776
//
// The queue is necessary to avoid ordering issues for synchronous commands.


// Why use true/false here? Why not just check the length of the queue?
// The goal is to detect "are we currently dispatching effects?" If we
// are, we need to bail and let the ongoing while loop handle things.
//
// Now say the queue has 1 element. When we dequeue the final element,
// the queue will be empty, but we are still actively dispatching effects.
// So you could get queue jumping in a really tricky category of cases.
//
var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ p: managers, q: cmdBag, r: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.p, fx.q, fx.r);
	}
	_Platform_effectsActive = false;
}


function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { i: _List_Nil, j: _List_Nil }
		});
	}
}


function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case 1:
			var home = bag.k;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.l);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case 2:
			for (var list = bag.m; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case 3:
			_Platform_gatherEffects(isCmd, bag.o, effectsDict, {
				s: bag.n,
				t: taggers
			});
			return;
	}
}


function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.t)
		{
			x = temp.s(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].e
		: _Platform_effectManagers[home].f;

	return A2(map, applyTaggers, value)
}


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { i: _List_Nil, j: _List_Nil };

	isCmd
		? (effects.i = _List_Cons(newEffect, effects.i))
		: (effects.j = _List_Cons(newEffect, effects.j));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		e: _Platform_outgoingPortMap,
		u: converter,
		a: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		f: _Platform_incomingPortMap,
		u: converter,
		a: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		$elm$core$Result$isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES
//
// Have DEBUG and PROD versions so that we can (1) give nicer errors in
// debug mode and (2) not pay for the bits needed for that in prod mode.
//


function _Platform_export_UNUSED(exports)
{
	scope['Elm']
		? _Platform_mergeExportsProd(scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


function _Platform_export(exports)
{
	scope['Elm']
		? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}




// HELPERS


var _VirtualDom_divertHrefToApp;

var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};


function _VirtualDom_appendChild(parent, child)
{
	parent.appendChild(child);
}

var _VirtualDom_init = F4(function(virtualNode, flagDecoder, debugMetadata, args)
{
	// NOTE: this function needs _Platform_export available to work

	/**_UNUSED/
	var node = args['node'];
	//*/
	/**/
	var node = args && args['node'] ? args['node'] : _Debug_crash(0);
	//*/

	node.parentNode.replaceChild(
		_VirtualDom_render(virtualNode, function() {}),
		node
	);

	return {};
});



// TEXT


function _VirtualDom_text(string)
{
	return {
		$: 0,
		a: string
	};
}



// NODE


var _VirtualDom_nodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 1,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_node = _VirtualDom_nodeNS(undefined);



// KEYED NODE


var _VirtualDom_keyedNodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 2,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_keyedNode = _VirtualDom_keyedNodeNS(undefined);



// CUSTOM


function _VirtualDom_custom(factList, model, render, diff)
{
	return {
		$: 3,
		d: _VirtualDom_organizeFacts(factList),
		g: model,
		h: render,
		i: diff
	};
}



// MAP


var _VirtualDom_map = F2(function(tagger, node)
{
	return {
		$: 4,
		j: tagger,
		k: node,
		b: 1 + (node.b || 0)
	};
});



// LAZY


function _VirtualDom_thunk(refs, thunk)
{
	return {
		$: 5,
		l: refs,
		m: thunk,
		k: undefined
	};
}

var _VirtualDom_lazy = F2(function(func, a)
{
	return _VirtualDom_thunk([func, a], function() {
		return func(a);
	});
});

var _VirtualDom_lazy2 = F3(function(func, a, b)
{
	return _VirtualDom_thunk([func, a, b], function() {
		return A2(func, a, b);
	});
});

var _VirtualDom_lazy3 = F4(function(func, a, b, c)
{
	return _VirtualDom_thunk([func, a, b, c], function() {
		return A3(func, a, b, c);
	});
});

var _VirtualDom_lazy4 = F5(function(func, a, b, c, d)
{
	return _VirtualDom_thunk([func, a, b, c, d], function() {
		return A4(func, a, b, c, d);
	});
});

var _VirtualDom_lazy5 = F6(function(func, a, b, c, d, e)
{
	return _VirtualDom_thunk([func, a, b, c, d, e], function() {
		return A5(func, a, b, c, d, e);
	});
});

var _VirtualDom_lazy6 = F7(function(func, a, b, c, d, e, f)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f], function() {
		return A6(func, a, b, c, d, e, f);
	});
});

var _VirtualDom_lazy7 = F8(function(func, a, b, c, d, e, f, g)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g], function() {
		return A7(func, a, b, c, d, e, f, g);
	});
});

var _VirtualDom_lazy8 = F9(function(func, a, b, c, d, e, f, g, h)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g, h], function() {
		return A8(func, a, b, c, d, e, f, g, h);
	});
});



// FACTS


var _VirtualDom_on = F2(function(key, handler)
{
	return {
		$: 'a0',
		n: key,
		o: handler
	};
});
var _VirtualDom_style = F2(function(key, value)
{
	return {
		$: 'a1',
		n: key,
		o: value
	};
});
var _VirtualDom_property = F2(function(key, value)
{
	return {
		$: 'a2',
		n: key,
		o: value
	};
});
var _VirtualDom_attribute = F2(function(key, value)
{
	return {
		$: 'a3',
		n: key,
		o: value
	};
});
var _VirtualDom_attributeNS = F3(function(namespace, key, value)
{
	return {
		$: 'a4',
		n: key,
		o: { f: namespace, o: value }
	};
});



// XSS ATTACK VECTOR CHECKS
//
// For some reason, tabs can appear in href protocols and it still works.
// So '\tjava\tSCRIPT:alert("!!!")' and 'javascript:alert("!!!")' are the same
// in practice. That is why _VirtualDom_RE_js and _VirtualDom_RE_js_html look
// so freaky.
//
// Pulling the regular expressions out to the top level gives a slight speed
// boost in small benchmarks (4-10%) but hoisting values to reduce allocation
// can be unpredictable in large programs where JIT may have a harder time with
// functions are not fully self-contained. The benefit is more that the js and
// js_html ones are so weird that I prefer to see them near each other.


var _VirtualDom_RE_script = /^script$/i;
var _VirtualDom_RE_on_formAction = /^(on|formAction$)/i;
var _VirtualDom_RE_js = /^\s*j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:/i;
var _VirtualDom_RE_js_html = /^\s*(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:|d\s*a\s*t\s*a\s*:\s*t\s*e\s*x\s*t\s*\/\s*h\s*t\s*m\s*l\s*(,|;))/i;


function _VirtualDom_noScript(tag)
{
	return _VirtualDom_RE_script.test(tag) ? 'p' : tag;
}

function _VirtualDom_noOnOrFormAction(key)
{
	return _VirtualDom_RE_on_formAction.test(key) ? 'data-' + key : key;
}

function _VirtualDom_noInnerHtmlOrFormAction(key)
{
	return key == 'innerHTML' || key == 'formAction' ? 'data-' + key : key;
}

function _VirtualDom_noJavaScriptUri(value)
{
	return _VirtualDom_RE_js.test(value)
		? /**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		? _Json_wrap(
			/**_UNUSED/''//*//**/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		) : value;
}



// MAP FACTS


var _VirtualDom_mapAttribute = F2(function(func, attr)
{
	return (attr.$ === 'a0')
		? A2(_VirtualDom_on, attr.n, _VirtualDom_mapHandler(func, attr.o))
		: attr;
});

function _VirtualDom_mapHandler(func, handler)
{
	var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

	// 0 = Normal
	// 1 = MayStopPropagation
	// 2 = MayPreventDefault
	// 3 = Custom

	return {
		$: handler.$,
		a:
			!tag
				? A2($elm$json$Json$Decode$map, func, handler.a)
				:
			A3($elm$json$Json$Decode$map2,
				tag < 3
					? _VirtualDom_mapEventTuple
					: _VirtualDom_mapEventRecord,
				$elm$json$Json$Decode$succeed(func),
				handler.a
			)
	};
}

var _VirtualDom_mapEventTuple = F2(function(func, tuple)
{
	return _Utils_Tuple2(func(tuple.a), tuple.b);
});

var _VirtualDom_mapEventRecord = F2(function(func, record)
{
	return {
		message: func(record.message),
		stopPropagation: record.stopPropagation,
		preventDefault: record.preventDefault
	}
});



// ORGANIZE FACTS


function _VirtualDom_organizeFacts(factList)
{
	for (var facts = {}; factList.b; factList = factList.b) // WHILE_CONS
	{
		var entry = factList.a;

		var tag = entry.$;
		var key = entry.n;
		var value = entry.o;

		if (tag === 'a2')
		{
			(key === 'className')
				? _VirtualDom_addClass(facts, key, _Json_unwrap(value))
				: facts[key] = _Json_unwrap(value);

			continue;
		}

		var subFacts = facts[tag] || (facts[tag] = {});
		(tag === 'a3' && key === 'class')
			? _VirtualDom_addClass(subFacts, key, value)
			: subFacts[key] = value;
	}

	return facts;
}

function _VirtualDom_addClass(object, key, newClass)
{
	var classes = object[key];
	object[key] = classes ? classes + ' ' + newClass : newClass;
}



// RENDER


function _VirtualDom_render(vNode, eventNode)
{
	var tag = vNode.$;

	if (tag === 5)
	{
		return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
	}

	if (tag === 0)
	{
		return _VirtualDom_doc.createTextNode(vNode.a);
	}

	if (tag === 4)
	{
		var subNode = vNode.k;
		var tagger = vNode.j;

		while (subNode.$ === 4)
		{
			typeof tagger !== 'object'
				? tagger = [tagger, subNode.j]
				: tagger.push(subNode.j);

			subNode = subNode.k;
		}

		var subEventRoot = { j: tagger, p: eventNode };
		var domNode = _VirtualDom_render(subNode, subEventRoot);
		domNode.elm_event_node_ref = subEventRoot;
		return domNode;
	}

	if (tag === 3)
	{
		var domNode = vNode.h(vNode.g);
		_VirtualDom_applyFacts(domNode, eventNode, vNode.d);
		return domNode;
	}

	// at this point `tag` must be 1 or 2

	var domNode = vNode.f
		? _VirtualDom_doc.createElementNS(vNode.f, vNode.c)
		: _VirtualDom_doc.createElement(vNode.c);

	if (_VirtualDom_divertHrefToApp && vNode.c == 'a')
	{
		domNode.addEventListener('click', _VirtualDom_divertHrefToApp(domNode));
	}

	_VirtualDom_applyFacts(domNode, eventNode, vNode.d);

	for (var kids = vNode.e, i = 0; i < kids.length; i++)
	{
		_VirtualDom_appendChild(domNode, _VirtualDom_render(tag === 1 ? kids[i] : kids[i].b, eventNode));
	}

	return domNode;
}



// APPLY FACTS


function _VirtualDom_applyFacts(domNode, eventNode, facts)
{
	for (var key in facts)
	{
		var value = facts[key];

		key === 'a1'
			? _VirtualDom_applyStyles(domNode, value)
			:
		key === 'a0'
			? _VirtualDom_applyEvents(domNode, eventNode, value)
			:
		key === 'a3'
			? _VirtualDom_applyAttrs(domNode, value)
			:
		key === 'a4'
			? _VirtualDom_applyAttrsNS(domNode, value)
			:
		((key !== 'value' && key !== 'checked') || domNode[key] !== value) && (domNode[key] = value);
	}
}



// APPLY STYLES


function _VirtualDom_applyStyles(domNode, styles)
{
	var domNodeStyle = domNode.style;

	for (var key in styles)
	{
		domNodeStyle[key] = styles[key];
	}
}



// APPLY ATTRS


function _VirtualDom_applyAttrs(domNode, attrs)
{
	for (var key in attrs)
	{
		var value = attrs[key];
		typeof value !== 'undefined'
			? domNode.setAttribute(key, value)
			: domNode.removeAttribute(key);
	}
}



// APPLY NAMESPACED ATTRS


function _VirtualDom_applyAttrsNS(domNode, nsAttrs)
{
	for (var key in nsAttrs)
	{
		var pair = nsAttrs[key];
		var namespace = pair.f;
		var value = pair.o;

		typeof value !== 'undefined'
			? domNode.setAttributeNS(namespace, key, value)
			: domNode.removeAttributeNS(namespace, key);
	}
}



// APPLY EVENTS


function _VirtualDom_applyEvents(domNode, eventNode, events)
{
	var allCallbacks = domNode.elmFs || (domNode.elmFs = {});

	for (var key in events)
	{
		var newHandler = events[key];
		var oldCallback = allCallbacks[key];

		if (!newHandler)
		{
			domNode.removeEventListener(key, oldCallback);
			allCallbacks[key] = undefined;
			continue;
		}

		if (oldCallback)
		{
			var oldHandler = oldCallback.q;
			if (oldHandler.$ === newHandler.$)
			{
				oldCallback.q = newHandler;
				continue;
			}
			domNode.removeEventListener(key, oldCallback);
		}

		oldCallback = _VirtualDom_makeCallback(eventNode, newHandler);
		domNode.addEventListener(key, oldCallback,
			_VirtualDom_passiveSupported
			&& { passive: $elm$virtual_dom$VirtualDom$toHandlerInt(newHandler) < 2 }
		);
		allCallbacks[key] = oldCallback;
	}
}



// PASSIVE EVENTS


var _VirtualDom_passiveSupported;

try
{
	window.addEventListener('t', null, Object.defineProperty({}, 'passive', {
		get: function() { _VirtualDom_passiveSupported = true; }
	}));
}
catch(e) {}



// EVENT HANDLERS


function _VirtualDom_makeCallback(eventNode, initialHandler)
{
	function callback(event)
	{
		var handler = callback.q;
		var result = _Json_runHelp(handler.a, event);

		if (!$elm$core$Result$isOk(result))
		{
			return;
		}

		var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

		// 0 = Normal
		// 1 = MayStopPropagation
		// 2 = MayPreventDefault
		// 3 = Custom

		var value = result.a;
		var message = !tag ? value : tag < 3 ? value.a : value.message;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.stopPropagation;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.preventDefault) && event.preventDefault(),
			eventNode
		);
		var tagger;
		var i;
		while (tagger = currentEventNode.j)
		{
			if (typeof tagger == 'function')
			{
				message = tagger(message);
			}
			else
			{
				for (var i = tagger.length; i--; )
				{
					message = tagger[i](message);
				}
			}
			currentEventNode = currentEventNode.p;
		}
		currentEventNode(message, stopPropagation); // stopPropagation implies isSync
	}

	callback.q = initialHandler;

	return callback;
}

function _VirtualDom_equalEvents(x, y)
{
	return x.$ == y.$ && _Json_equality(x.a, y.a);
}



// DIFF


// TODO: Should we do patches like in iOS?
//
// type Patch
//   = At Int Patch
//   | Batch (List Patch)
//   | Change ...
//
// How could it not be better?
//
function _VirtualDom_diff(x, y)
{
	var patches = [];
	_VirtualDom_diffHelp(x, y, patches, 0);
	return patches;
}


function _VirtualDom_pushPatch(patches, type, index, data)
{
	var patch = {
		$: type,
		r: index,
		s: data,
		t: undefined,
		u: undefined
	};
	patches.push(patch);
	return patch;
}


function _VirtualDom_diffHelp(x, y, patches, index)
{
	if (x === y)
	{
		return;
	}

	var xType = x.$;
	var yType = y.$;

	// Bail if you run into different types of nodes. Implies that the
	// structure has changed significantly and it's not worth a diff.
	if (xType !== yType)
	{
		if (xType === 1 && yType === 2)
		{
			y = _VirtualDom_dekey(y);
			yType = 1;
		}
		else
		{
			_VirtualDom_pushPatch(patches, 0, index, y);
			return;
		}
	}

	// Now we know that both nodes are the same $.
	switch (yType)
	{
		case 5:
			var xRefs = x.l;
			var yRefs = y.l;
			var i = xRefs.length;
			var same = i === yRefs.length;
			while (same && i--)
			{
				same = xRefs[i] === yRefs[i];
			}
			if (same)
			{
				y.k = x.k;
				return;
			}
			y.k = y.m();
			var subPatches = [];
			_VirtualDom_diffHelp(x.k, y.k, subPatches, 0);
			subPatches.length > 0 && _VirtualDom_pushPatch(patches, 1, index, subPatches);
			return;

		case 4:
			// gather nested taggers
			var xTaggers = x.j;
			var yTaggers = y.j;
			var nesting = false;

			var xSubNode = x.k;
			while (xSubNode.$ === 4)
			{
				nesting = true;

				typeof xTaggers !== 'object'
					? xTaggers = [xTaggers, xSubNode.j]
					: xTaggers.push(xSubNode.j);

				xSubNode = xSubNode.k;
			}

			var ySubNode = y.k;
			while (ySubNode.$ === 4)
			{
				nesting = true;

				typeof yTaggers !== 'object'
					? yTaggers = [yTaggers, ySubNode.j]
					: yTaggers.push(ySubNode.j);

				ySubNode = ySubNode.k;
			}

			// Just bail if different numbers of taggers. This implies the
			// structure of the virtual DOM has changed.
			if (nesting && xTaggers.length !== yTaggers.length)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			// check if taggers are "the same"
			if (nesting ? !_VirtualDom_pairwiseRefEqual(xTaggers, yTaggers) : xTaggers !== yTaggers)
			{
				_VirtualDom_pushPatch(patches, 2, index, yTaggers);
			}

			// diff everything below the taggers
			_VirtualDom_diffHelp(xSubNode, ySubNode, patches, index + 1);
			return;

		case 0:
			if (x.a !== y.a)
			{
				_VirtualDom_pushPatch(patches, 3, index, y.a);
			}
			return;

		case 1:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKids);
			return;

		case 2:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKeyedKids);
			return;

		case 3:
			if (x.h !== y.h)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
			factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

			var patch = y.i(x.g, y.g);
			patch && _VirtualDom_pushPatch(patches, 5, index, patch);

			return;
	}
}

// assumes the incoming arrays are the same length
function _VirtualDom_pairwiseRefEqual(as, bs)
{
	for (var i = 0; i < as.length; i++)
	{
		if (as[i] !== bs[i])
		{
			return false;
		}
	}

	return true;
}

function _VirtualDom_diffNodes(x, y, patches, index, diffKids)
{
	// Bail if obvious indicators have changed. Implies more serious
	// structural changes such that it's not worth it to diff.
	if (x.c !== y.c || x.f !== y.f)
	{
		_VirtualDom_pushPatch(patches, 0, index, y);
		return;
	}

	var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
	factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

	diffKids(x, y, patches, index);
}



// DIFF FACTS


// TODO Instead of creating a new diff object, it's possible to just test if
// there *is* a diff. During the actual patch, do the diff again and make the
// modifications directly. This way, there's no new allocations. Worth it?
function _VirtualDom_diffFacts(x, y, category)
{
	var diff;

	// look for changes and removals
	for (var xKey in x)
	{
		if (xKey === 'a1' || xKey === 'a0' || xKey === 'a3' || xKey === 'a4')
		{
			var subDiff = _VirtualDom_diffFacts(x[xKey], y[xKey] || {}, xKey);
			if (subDiff)
			{
				diff = diff || {};
				diff[xKey] = subDiff;
			}
			continue;
		}

		// remove if not in the new facts
		if (!(xKey in y))
		{
			diff = diff || {};
			diff[xKey] =
				!category
					? (typeof x[xKey] === 'string' ? '' : null)
					:
				(category === 'a1')
					? ''
					:
				(category === 'a0' || category === 'a3')
					? undefined
					:
				{ f: x[xKey].f, o: undefined };

			continue;
		}

		var xValue = x[xKey];
		var yValue = y[xKey];

		// reference equal, so don't worry about it
		if (xValue === yValue && xKey !== 'value' && xKey !== 'checked'
			|| category === 'a0' && _VirtualDom_equalEvents(xValue, yValue))
		{
			continue;
		}

		diff = diff || {};
		diff[xKey] = yValue;
	}

	// add new stuff
	for (var yKey in y)
	{
		if (!(yKey in x))
		{
			diff = diff || {};
			diff[yKey] = y[yKey];
		}
	}

	return diff;
}



// DIFF KIDS


function _VirtualDom_diffKids(xParent, yParent, patches, index)
{
	var xKids = xParent.e;
	var yKids = yParent.e;

	var xLen = xKids.length;
	var yLen = yKids.length;

	// FIGURE OUT IF THERE ARE INSERTS OR REMOVALS

	if (xLen > yLen)
	{
		_VirtualDom_pushPatch(patches, 6, index, {
			v: yLen,
			i: xLen - yLen
		});
	}
	else if (xLen < yLen)
	{
		_VirtualDom_pushPatch(patches, 7, index, {
			v: xLen,
			e: yKids
		});
	}

	// PAIRWISE DIFF EVERYTHING ELSE

	for (var minLen = xLen < yLen ? xLen : yLen, i = 0; i < minLen; i++)
	{
		var xKid = xKids[i];
		_VirtualDom_diffHelp(xKid, yKids[i], patches, ++index);
		index += xKid.b || 0;
	}
}



// KEYED DIFF


function _VirtualDom_diffKeyedKids(xParent, yParent, patches, rootIndex)
{
	var localPatches = [];

	var changes = {}; // Dict String Entry
	var inserts = []; // Array { index : Int, entry : Entry }
	// type Entry = { tag : String, vnode : VNode, index : Int, data : _ }

	var xKids = xParent.e;
	var yKids = yParent.e;
	var xLen = xKids.length;
	var yLen = yKids.length;
	var xIndex = 0;
	var yIndex = 0;

	var index = rootIndex;

	while (xIndex < xLen && yIndex < yLen)
	{
		var x = xKids[xIndex];
		var y = yKids[yIndex];

		var xKey = x.a;
		var yKey = y.a;
		var xNode = x.b;
		var yNode = y.b;

		var newMatch = undefined;
		var oldMatch = undefined;

		// check if keys match

		if (xKey === yKey)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNode, localPatches, index);
			index += xNode.b || 0;

			xIndex++;
			yIndex++;
			continue;
		}

		// look ahead 1 to detect insertions and removals.

		var xNext = xKids[xIndex + 1];
		var yNext = yKids[yIndex + 1];

		if (xNext)
		{
			var xNextKey = xNext.a;
			var xNextNode = xNext.b;
			oldMatch = yKey === xNextKey;
		}

		if (yNext)
		{
			var yNextKey = yNext.a;
			var yNextNode = yNext.b;
			newMatch = xKey === yNextKey;
		}


		// swap x and y
		if (newMatch && oldMatch)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			_VirtualDom_insertNode(changes, localPatches, xKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNextNode, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		// insert y
		if (newMatch)
		{
			index++;
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			index += xNode.b || 0;

			xIndex += 1;
			yIndex += 2;
			continue;
		}

		// remove x
		if (oldMatch)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 1;
			continue;
		}

		// remove x, insert y
		if (xNext && xNextKey === yNextKey)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNextNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		break;
	}

	// eat up any remaining nodes with removeNode and insertNode

	while (xIndex < xLen)
	{
		index++;
		var x = xKids[xIndex];
		var xNode = x.b;
		_VirtualDom_removeNode(changes, localPatches, x.a, xNode, index);
		index += xNode.b || 0;
		xIndex++;
	}

	while (yIndex < yLen)
	{
		var endInserts = endInserts || [];
		var y = yKids[yIndex];
		_VirtualDom_insertNode(changes, localPatches, y.a, y.b, undefined, endInserts);
		yIndex++;
	}

	if (localPatches.length > 0 || inserts.length > 0 || endInserts)
	{
		_VirtualDom_pushPatch(patches, 8, rootIndex, {
			w: localPatches,
			x: inserts,
			y: endInserts
		});
	}
}



// CHANGES FROM KEYED DIFF


var _VirtualDom_POSTFIX = '_elmW6BL';


function _VirtualDom_insertNode(changes, localPatches, key, vnode, yIndex, inserts)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		entry = {
			c: 0,
			z: vnode,
			r: yIndex,
			s: undefined
		};

		inserts.push({ r: yIndex, A: entry });
		changes[key] = entry;

		return;
	}

	// this key was removed earlier, a match!
	if (entry.c === 1)
	{
		inserts.push({ r: yIndex, A: entry });

		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(entry.z, vnode, subPatches, entry.r);
		entry.r = yIndex;
		entry.s.s = {
			w: subPatches,
			A: entry
		};

		return;
	}

	// this key has already been inserted or moved, a duplicate!
	_VirtualDom_insertNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, yIndex, inserts);
}


function _VirtualDom_removeNode(changes, localPatches, key, vnode, index)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		var patch = _VirtualDom_pushPatch(localPatches, 9, index, undefined);

		changes[key] = {
			c: 1,
			z: vnode,
			r: index,
			s: patch
		};

		return;
	}

	// this key was inserted earlier, a match!
	if (entry.c === 0)
	{
		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(vnode, entry.z, subPatches, index);

		_VirtualDom_pushPatch(localPatches, 9, index, {
			w: subPatches,
			A: entry
		});

		return;
	}

	// this key has already been removed or moved, a duplicate!
	_VirtualDom_removeNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, index);
}



// ADD DOM NODES
//
// Each DOM node has an "index" assigned in order of traversal. It is important
// to minimize our crawl over the actual DOM, so these indexes (along with the
// descendantsCount of virtual nodes) let us skip touching entire subtrees of
// the DOM if we know there are no patches there.


function _VirtualDom_addDomNodes(domNode, vNode, patches, eventNode)
{
	_VirtualDom_addDomNodesHelp(domNode, vNode, patches, 0, 0, vNode.b, eventNode);
}


// assumes `patches` is non-empty and indexes increase monotonically.
function _VirtualDom_addDomNodesHelp(domNode, vNode, patches, i, low, high, eventNode)
{
	var patch = patches[i];
	var index = patch.r;

	while (index === low)
	{
		var patchType = patch.$;

		if (patchType === 1)
		{
			_VirtualDom_addDomNodes(domNode, vNode.k, patch.s, eventNode);
		}
		else if (patchType === 8)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var subPatches = patch.s.w;
			if (subPatches.length > 0)
			{
				_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
			}
		}
		else if (patchType === 9)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var data = patch.s;
			if (data)
			{
				data.A.s = domNode;
				var subPatches = data.w;
				if (subPatches.length > 0)
				{
					_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
				}
			}
		}
		else
		{
			patch.t = domNode;
			patch.u = eventNode;
		}

		i++;

		if (!(patch = patches[i]) || (index = patch.r) > high)
		{
			return i;
		}
	}

	var tag = vNode.$;

	if (tag === 4)
	{
		var subNode = vNode.k;

		while (subNode.$ === 4)
		{
			subNode = subNode.k;
		}

		return _VirtualDom_addDomNodesHelp(domNode, subNode, patches, i, low + 1, high, domNode.elm_event_node_ref);
	}

	// tag must be 1 or 2 at this point

	var vKids = vNode.e;
	var childNodes = domNode.childNodes;
	for (var j = 0; j < vKids.length; j++)
	{
		low++;
		var vKid = tag === 1 ? vKids[j] : vKids[j].b;
		var nextLow = low + (vKid.b || 0);
		if (low <= index && index <= nextLow)
		{
			i = _VirtualDom_addDomNodesHelp(childNodes[j], vKid, patches, i, low, nextLow, eventNode);
			if (!(patch = patches[i]) || (index = patch.r) > high)
			{
				return i;
			}
		}
		low = nextLow;
	}
	return i;
}



// APPLY PATCHES


function _VirtualDom_applyPatches(rootDomNode, oldVirtualNode, patches, eventNode)
{
	if (patches.length === 0)
	{
		return rootDomNode;
	}

	_VirtualDom_addDomNodes(rootDomNode, oldVirtualNode, patches, eventNode);
	return _VirtualDom_applyPatchesHelp(rootDomNode, patches);
}

function _VirtualDom_applyPatchesHelp(rootDomNode, patches)
{
	for (var i = 0; i < patches.length; i++)
	{
		var patch = patches[i];
		var localDomNode = patch.t
		var newNode = _VirtualDom_applyPatch(localDomNode, patch);
		if (localDomNode === rootDomNode)
		{
			rootDomNode = newNode;
		}
	}
	return rootDomNode;
}

function _VirtualDom_applyPatch(domNode, patch)
{
	switch (patch.$)
	{
		case 0:
			return _VirtualDom_applyPatchRedraw(domNode, patch.s, patch.u);

		case 4:
			_VirtualDom_applyFacts(domNode, patch.u, patch.s);
			return domNode;

		case 3:
			domNode.replaceData(0, domNode.length, patch.s);
			return domNode;

		case 1:
			return _VirtualDom_applyPatchesHelp(domNode, patch.s);

		case 2:
			if (domNode.elm_event_node_ref)
			{
				domNode.elm_event_node_ref.j = patch.s;
			}
			else
			{
				domNode.elm_event_node_ref = { j: patch.s, p: patch.u };
			}
			return domNode;

		case 6:
			var data = patch.s;
			for (var i = 0; i < data.i; i++)
			{
				domNode.removeChild(domNode.childNodes[data.v]);
			}
			return domNode;

		case 7:
			var data = patch.s;
			var kids = data.e;
			var i = data.v;
			var theEnd = domNode.childNodes[i];
			for (; i < kids.length; i++)
			{
				domNode.insertBefore(_VirtualDom_render(kids[i], patch.u), theEnd);
			}
			return domNode;

		case 9:
			var data = patch.s;
			if (!data)
			{
				domNode.parentNode.removeChild(domNode);
				return domNode;
			}
			var entry = data.A;
			if (typeof entry.r !== 'undefined')
			{
				domNode.parentNode.removeChild(domNode);
			}
			entry.s = _VirtualDom_applyPatchesHelp(domNode, data.w);
			return domNode;

		case 8:
			return _VirtualDom_applyPatchReorder(domNode, patch);

		case 5:
			return patch.s(domNode);

		default:
			_Debug_crash(10); // 'Ran into an unknown patch!'
	}
}


function _VirtualDom_applyPatchRedraw(domNode, vNode, eventNode)
{
	var parentNode = domNode.parentNode;
	var newNode = _VirtualDom_render(vNode, eventNode);

	if (!newNode.elm_event_node_ref)
	{
		newNode.elm_event_node_ref = domNode.elm_event_node_ref;
	}

	if (parentNode && newNode !== domNode)
	{
		parentNode.replaceChild(newNode, domNode);
	}
	return newNode;
}


function _VirtualDom_applyPatchReorder(domNode, patch)
{
	var data = patch.s;

	// remove end inserts
	var frag = _VirtualDom_applyPatchReorderEndInsertsHelp(data.y, patch);

	// removals
	domNode = _VirtualDom_applyPatchesHelp(domNode, data.w);

	// inserts
	var inserts = data.x;
	for (var i = 0; i < inserts.length; i++)
	{
		var insert = inserts[i];
		var entry = insert.A;
		var node = entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u);
		domNode.insertBefore(node, domNode.childNodes[insert.r]);
	}

	// add end inserts
	if (frag)
	{
		_VirtualDom_appendChild(domNode, frag);
	}

	return domNode;
}


function _VirtualDom_applyPatchReorderEndInsertsHelp(endInserts, patch)
{
	if (!endInserts)
	{
		return;
	}

	var frag = _VirtualDom_doc.createDocumentFragment();
	for (var i = 0; i < endInserts.length; i++)
	{
		var insert = endInserts[i];
		var entry = insert.A;
		_VirtualDom_appendChild(frag, entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u)
		);
	}
	return frag;
}


function _VirtualDom_virtualize(node)
{
	// TEXT NODES

	if (node.nodeType === 3)
	{
		return _VirtualDom_text(node.textContent);
	}


	// WEIRD NODES

	if (node.nodeType !== 1)
	{
		return _VirtualDom_text('');
	}


	// ELEMENT NODES

	var attrList = _List_Nil;
	var attrs = node.attributes;
	for (var i = attrs.length; i--; )
	{
		var attr = attrs[i];
		var name = attr.name;
		var value = attr.value;
		attrList = _List_Cons( A2(_VirtualDom_attribute, name, value), attrList );
	}

	var tag = node.tagName.toLowerCase();
	var kidList = _List_Nil;
	var kids = node.childNodes;

	for (var i = kids.length; i--; )
	{
		kidList = _List_Cons(_VirtualDom_virtualize(kids[i]), kidList);
	}
	return A3(_VirtualDom_node, tag, attrList, kidList);
}

function _VirtualDom_dekey(keyedNode)
{
	var keyedKids = keyedNode.e;
	var len = keyedKids.length;
	var kids = new Array(len);
	for (var i = 0; i < len; i++)
	{
		kids[i] = keyedKids[i].b;
	}

	return {
		$: 1,
		c: keyedNode.c,
		d: keyedNode.d,
		e: kids,
		f: keyedNode.f,
		b: keyedNode.b
	};
}




// ELEMENT


var _Debugger_element;

var _Browser_element = _Debugger_element || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.init,
		impl.update,
		impl.subscriptions,
		function(sendToApp, initialModel) {
			var view = impl.view;
			/**_UNUSED/
			var domNode = args['node'];
			//*/
			/**/
			var domNode = args && args['node'] ? args['node'] : _Debug_crash(0);
			//*/
			var currNode = _VirtualDom_virtualize(domNode);

			return _Browser_makeAnimator(initialModel, function(model)
			{
				var nextNode = view(model);
				var patches = _VirtualDom_diff(currNode, nextNode);
				domNode = _VirtualDom_applyPatches(domNode, currNode, patches, sendToApp);
				currNode = nextNode;
			});
		}
	);
});



// DOCUMENT


var _Debugger_document;

var _Browser_document = _Debugger_document || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.init,
		impl.update,
		impl.subscriptions,
		function(sendToApp, initialModel) {
			var divertHrefToApp = impl.setup && impl.setup(sendToApp)
			var view = impl.view;
			var title = _VirtualDom_doc.title;
			var bodyNode = _VirtualDom_doc.body;
			var currNode = _VirtualDom_virtualize(bodyNode);
			return _Browser_makeAnimator(initialModel, function(model)
			{
				_VirtualDom_divertHrefToApp = divertHrefToApp;
				var doc = view(model);
				var nextNode = _VirtualDom_node('body')(_List_Nil)(doc.body);
				var patches = _VirtualDom_diff(currNode, nextNode);
				bodyNode = _VirtualDom_applyPatches(bodyNode, currNode, patches, sendToApp);
				currNode = nextNode;
				_VirtualDom_divertHrefToApp = 0;
				(title !== doc.title) && (_VirtualDom_doc.title = title = doc.title);
			});
		}
	);
});



// ANIMATION


var _Browser_cancelAnimationFrame =
	typeof cancelAnimationFrame !== 'undefined'
		? cancelAnimationFrame
		: function(id) { clearTimeout(id); };

var _Browser_requestAnimationFrame =
	typeof requestAnimationFrame !== 'undefined'
		? requestAnimationFrame
		: function(callback) { return setTimeout(callback, 1000 / 60); };


function _Browser_makeAnimator(model, draw)
{
	draw(model);

	var state = 0;

	function updateIfNeeded()
	{
		state = state === 1
			? 0
			: ( _Browser_requestAnimationFrame(updateIfNeeded), draw(model), 1 );
	}

	return function(nextModel, isSync)
	{
		model = nextModel;

		isSync
			? ( draw(model),
				state === 2 && (state = 1)
				)
			: ( state === 0 && _Browser_requestAnimationFrame(updateIfNeeded),
				state = 2
				);
	};
}



// APPLICATION


function _Browser_application(impl)
{
	var onUrlChange = impl.onUrlChange;
	var onUrlRequest = impl.onUrlRequest;
	var key = function() { key.a(onUrlChange(_Browser_getUrl())); };

	return _Browser_document({
		setup: function(sendToApp)
		{
			key.a = sendToApp;
			_Browser_window.addEventListener('popstate', key);
			_Browser_window.navigator.userAgent.indexOf('Trident') < 0 || _Browser_window.addEventListener('hashchange', key);

			return F2(function(domNode, event)
			{
				if (!event.ctrlKey && !event.metaKey && !event.shiftKey && event.button < 1 && !domNode.target && !domNode.hasAttribute('download'))
				{
					event.preventDefault();
					var href = domNode.href;
					var curr = _Browser_getUrl();
					var next = $elm$url$Url$fromString(href).a;
					sendToApp(onUrlRequest(
						(next
							&& curr.protocol === next.protocol
							&& curr.host === next.host
							&& curr.port_.a === next.port_.a
						)
							? $elm$browser$Browser$Internal(next)
							: $elm$browser$Browser$External(href)
					));
				}
			});
		},
		init: function(flags)
		{
			return A3(impl.init, flags, _Browser_getUrl(), key);
		},
		view: impl.view,
		update: impl.update,
		subscriptions: impl.subscriptions
	});
}

function _Browser_getUrl()
{
	return $elm$url$Url$fromString(_VirtualDom_doc.location.href).a || _Debug_crash(1);
}

var _Browser_go = F2(function(key, n)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		n && history.go(n);
		key();
	}));
});

var _Browser_pushUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.pushState({}, '', url);
		key();
	}));
});

var _Browser_replaceUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.replaceState({}, '', url);
		key();
	}));
});



// GLOBAL EVENTS


var _Browser_fakeNode = { addEventListener: function() {}, removeEventListener: function() {} };
var _Browser_doc = typeof document !== 'undefined' ? document : _Browser_fakeNode;
var _Browser_window = typeof window !== 'undefined' ? window : _Browser_fakeNode;

var _Browser_on = F3(function(node, eventName, sendToSelf)
{
	return _Scheduler_spawn(_Scheduler_binding(function(callback)
	{
		function handler(event)	{ _Scheduler_rawSpawn(sendToSelf(event)); }
		node.addEventListener(eventName, handler, _VirtualDom_passiveSupported && { passive: true });
		return function() { node.removeEventListener(eventName, handler); };
	}));
});

var _Browser_decodeEvent = F2(function(decoder, event)
{
	var result = _Json_runHelp(decoder, event);
	return $elm$core$Result$isOk(result) ? $elm$core$Maybe$Just(result.a) : $elm$core$Maybe$Nothing;
});



// PAGE VISIBILITY


function _Browser_visibilityInfo()
{
	return (typeof _VirtualDom_doc.hidden !== 'undefined')
		? { hidden: 'hidden', change: 'visibilitychange' }
		:
	(typeof _VirtualDom_doc.mozHidden !== 'undefined')
		? { hidden: 'mozHidden', change: 'mozvisibilitychange' }
		:
	(typeof _VirtualDom_doc.msHidden !== 'undefined')
		? { hidden: 'msHidden', change: 'msvisibilitychange' }
		:
	(typeof _VirtualDom_doc.webkitHidden !== 'undefined')
		? { hidden: 'webkitHidden', change: 'webkitvisibilitychange' }
		: { hidden: 'hidden', change: 'visibilitychange' };
}



// ANIMATION FRAMES


function _Browser_rAF()
{
	return _Scheduler_binding(function(callback)
	{
		var id = _Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(Date.now()));
		});

		return function() {
			_Browser_cancelAnimationFrame(id);
		};
	});
}


function _Browser_now()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(Date.now()));
	});
}



// DOM STUFF


function _Browser_withNode(id, doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			var node = document.getElementById(id);
			callback(node
				? _Scheduler_succeed(doStuff(node))
				: _Scheduler_fail($elm$browser$Browser$Dom$NotFound(id))
			);
		});
	});
}


function _Browser_withWindow(doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(doStuff()));
		});
	});
}


// FOCUS and BLUR


var _Browser_call = F2(function(functionName, id)
{
	return _Browser_withNode(id, function(node) {
		node[functionName]();
		return _Utils_Tuple0;
	});
});



// WINDOW VIEWPORT


function _Browser_getViewport()
{
	return {
		scene: _Browser_getScene(),
		viewport: {
			x: _Browser_window.pageXOffset,
			y: _Browser_window.pageYOffset,
			width: _Browser_doc.documentElement.clientWidth,
			height: _Browser_doc.documentElement.clientHeight
		}
	};
}

function _Browser_getScene()
{
	var body = _Browser_doc.body;
	var elem = _Browser_doc.documentElement;
	return {
		width: Math.max(body.scrollWidth, body.offsetWidth, elem.scrollWidth, elem.offsetWidth, elem.clientWidth),
		height: Math.max(body.scrollHeight, body.offsetHeight, elem.scrollHeight, elem.offsetHeight, elem.clientHeight)
	};
}

var _Browser_setViewport = F2(function(x, y)
{
	return _Browser_withWindow(function()
	{
		_Browser_window.scroll(x, y);
		return _Utils_Tuple0;
	});
});



// ELEMENT VIEWPORT


function _Browser_getViewportOf(id)
{
	return _Browser_withNode(id, function(node)
	{
		return {
			scene: {
				width: node.scrollWidth,
				height: node.scrollHeight
			},
			viewport: {
				x: node.scrollLeft,
				y: node.scrollTop,
				width: node.clientWidth,
				height: node.clientHeight
			}
		};
	});
}


var _Browser_setViewportOf = F3(function(id, x, y)
{
	return _Browser_withNode(id, function(node)
	{
		node.scrollLeft = x;
		node.scrollTop = y;
		return _Utils_Tuple0;
	});
});



// ELEMENT


function _Browser_getElement(id)
{
	return _Browser_withNode(id, function(node)
	{
		var rect = node.getBoundingClientRect();
		var x = _Browser_window.pageXOffset;
		var y = _Browser_window.pageYOffset;
		return {
			scene: _Browser_getScene(),
			viewport: {
				x: x,
				y: y,
				width: _Browser_doc.documentElement.clientWidth,
				height: _Browser_doc.documentElement.clientHeight
			},
			element: {
				x: x + rect.left,
				y: y + rect.top,
				width: rect.width,
				height: rect.height
			}
		};
	});
}



// LOAD and RELOAD


function _Browser_reload(skipCache)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		_VirtualDom_doc.location.reload(skipCache);
	}));
}

function _Browser_load(url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		try
		{
			_Browser_window.location = url;
		}
		catch(err)
		{
			// Only Firefox can throw a NS_ERROR_MALFORMED_URI exception here.
			// Other browsers reload the page, so let's be consistent about that.
			_VirtualDom_doc.location.reload(false);
		}
	}));
}



function _Time_now(millisToPosix)
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(millisToPosix(Date.now())));
	});
}

var _Time_setInterval = F2(function(interval, task)
{
	return _Scheduler_binding(function(callback)
	{
		var id = setInterval(function() { _Scheduler_rawSpawn(task); }, interval);
		return function() { clearInterval(id); };
	});
});

function _Time_here()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(
			A2($elm$time$Time$customZone, -(new Date().getTimezoneOffset()), _List_Nil)
		));
	});
}


function _Time_getZoneName()
{
	return _Scheduler_binding(function(callback)
	{
		try
		{
			var name = $elm$time$Time$Name(Intl.DateTimeFormat().resolvedOptions().timeZone);
		}
		catch (e)
		{
			var name = $elm$time$Time$Offset(new Date().getTimezoneOffset());
		}
		callback(_Scheduler_succeed(name));
	});
}



// SEND REQUEST

var _Http_toTask = F3(function(router, toTask, request)
{
	return _Scheduler_binding(function(callback)
	{
		function done(response) {
			callback(toTask(request.expect.a(response)));
		}

		var xhr = new XMLHttpRequest();
		xhr.addEventListener('error', function() { done($elm$http$Http$NetworkError_); });
		xhr.addEventListener('timeout', function() { done($elm$http$Http$Timeout_); });
		xhr.addEventListener('load', function() { done(_Http_toResponse(request.expect.b, xhr)); });
		$elm$core$Maybe$isJust(request.tracker) && _Http_track(router, xhr, request.tracker.a);

		try {
			xhr.open(request.method, request.url, true);
		} catch (e) {
			return done($elm$http$Http$BadUrl_(request.url));
		}

		_Http_configureRequest(xhr, request);

		request.body.a && xhr.setRequestHeader('Content-Type', request.body.a);
		xhr.send(request.body.b);

		return function() { xhr.c = true; xhr.abort(); };
	});
});


// CONFIGURE

function _Http_configureRequest(xhr, request)
{
	for (var headers = request.headers; headers.b; headers = headers.b) // WHILE_CONS
	{
		xhr.setRequestHeader(headers.a.a, headers.a.b);
	}
	xhr.timeout = request.timeout.a || 0;
	xhr.responseType = request.expect.d;
	xhr.withCredentials = request.allowCookiesFromOtherDomains;
}


// RESPONSES

function _Http_toResponse(toBody, xhr)
{
	return A2(
		200 <= xhr.status && xhr.status < 300 ? $elm$http$Http$GoodStatus_ : $elm$http$Http$BadStatus_,
		_Http_toMetadata(xhr),
		toBody(xhr.response)
	);
}


// METADATA

function _Http_toMetadata(xhr)
{
	return {
		url: xhr.responseURL,
		statusCode: xhr.status,
		statusText: xhr.statusText,
		headers: _Http_parseHeaders(xhr.getAllResponseHeaders())
	};
}


// HEADERS

function _Http_parseHeaders(rawHeaders)
{
	if (!rawHeaders)
	{
		return $elm$core$Dict$empty;
	}

	var headers = $elm$core$Dict$empty;
	var headerPairs = rawHeaders.split('\r\n');
	for (var i = headerPairs.length; i--; )
	{
		var headerPair = headerPairs[i];
		var index = headerPair.indexOf(': ');
		if (index > 0)
		{
			var key = headerPair.substring(0, index);
			var value = headerPair.substring(index + 2);

			headers = A3($elm$core$Dict$update, key, function(oldValue) {
				return $elm$core$Maybe$Just($elm$core$Maybe$isJust(oldValue)
					? value + ', ' + oldValue.a
					: value
				);
			}, headers);
		}
	}
	return headers;
}


// EXPECT

var _Http_expect = F3(function(type, toBody, toValue)
{
	return {
		$: 0,
		d: type,
		b: toBody,
		a: toValue
	};
});

var _Http_mapExpect = F2(function(func, expect)
{
	return {
		$: 0,
		d: expect.d,
		b: expect.b,
		a: function(x) { return func(expect.a(x)); }
	};
});

function _Http_toDataView(arrayBuffer)
{
	return new DataView(arrayBuffer);
}


// BODY and PARTS

var _Http_emptyBody = { $: 0 };
var _Http_pair = F2(function(a, b) { return { $: 0, a: a, b: b }; });

function _Http_toFormData(parts)
{
	for (var formData = new FormData(); parts.b; parts = parts.b) // WHILE_CONS
	{
		var part = parts.a;
		formData.append(part.a, part.b);
	}
	return formData;
}

var _Http_bytesToBlob = F2(function(mime, bytes)
{
	return new Blob([bytes], { type: mime });
});


// PROGRESS

function _Http_track(router, xhr, tracker)
{
	// TODO check out lengthComputable on loadstart event

	xhr.upload.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Sending({
			sent: event.loaded,
			size: event.total
		}))));
	});
	xhr.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Receiving({
			received: event.loaded,
			size: event.lengthComputable ? $elm$core$Maybe$Just(event.total) : $elm$core$Maybe$Nothing
		}))));
	});
}


var _Bitwise_and = F2(function(a, b)
{
	return a & b;
});

var _Bitwise_or = F2(function(a, b)
{
	return a | b;
});

var _Bitwise_xor = F2(function(a, b)
{
	return a ^ b;
});

function _Bitwise_complement(a)
{
	return ~a;
};

var _Bitwise_shiftLeftBy = F2(function(offset, a)
{
	return a << offset;
});

var _Bitwise_shiftRightBy = F2(function(offset, a)
{
	return a >> offset;
});

var _Bitwise_shiftRightZfBy = F2(function(offset, a)
{
	return a >>> offset;
});
var $elm$core$List$cons = _List_cons;
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr$ = function (func, baseCase, _v0) {
	var tree = _v0.c;
	var tail = _v0.d;
	var helper = F2(
		function (node, acc) {
			if (node.$ === 'SubTree') {
				var subTree = node.a;
				return A3($elm$core$Elm$JsArray$foldr, helper, acc, subTree);
			} else {
				var values = node.a;
				return A3($elm$core$Elm$JsArray$foldr, func, acc, values);
			}
		});
	return A3(
		$elm$core$Elm$JsArray$foldr,
		helper,
		A3($elm$core$Elm$JsArray$foldr, func, baseCase, tail),
		tree);
};
var $elm$core$Array$foldr = F3($elm$core$Array$foldr$);
var $elm$core$Array$toList = function (array) {
	return $elm$core$Array$foldr$($elm$core$List$cons, _List_Nil, array);
};
var $elm$core$Dict$foldr$ = function (func, acc, t) {
	foldr:
	while (true) {
		if (t.$ === 'RBEmpty_elm_builtin') {
			return acc;
		} else {
			var key = t.b;
			var value = t.c;
			var left = t.d;
			var right = t.e;
			var $temp$acc = A3(
				func,
				key,
				value,
				$elm$core$Dict$foldr$(func, acc, right)),
				$temp$t = left;
			acc = $temp$acc;
			t = $temp$t;
			continue foldr;
		}
	}
};
var $elm$core$Dict$foldr = F3($elm$core$Dict$foldr$);
var $elm$core$Dict$toList = function (dict) {
	return $elm$core$Dict$foldr$(
		F3(
			function (key, value, list) {
				return A2(
					$elm$core$List$cons,
					_Utils_Tuple2(key, value),
					list);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Dict$keys = function (dict) {
	return $elm$core$Dict$foldr$(
		F3(
			function (key, value, keyList) {
				return A2($elm$core$List$cons, key, keyList);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Set$toList = function (_v0) {
	var dict = _v0.a;
	return $elm$core$Dict$keys(dict);
};
var $elm$core$Basics$EQ = {$: 'EQ'};
var $elm$core$Basics$GT = {$: 'GT'};
var $elm$core$Basics$LT = {$: 'LT'};
var $author$project$Neat$Dashboard$Tick = function (a) {
	return {$: 'Tick', a: a};
};
var $elm$core$Result$Err = function (a) {
	return {$: 'Err', a: a};
};
var $elm$json$Json$Decode$Failure$ = function (a, b) {
	return {$: 'Failure', a: a, b: b};
};
var $elm$json$Json$Decode$Failure = F2($elm$json$Json$Decode$Failure$);
var $elm$json$Json$Decode$Field$ = function (a, b) {
	return {$: 'Field', a: a, b: b};
};
var $elm$json$Json$Decode$Field = F2($elm$json$Json$Decode$Field$);
var $elm$json$Json$Decode$Index$ = function (a, b) {
	return {$: 'Index', a: a, b: b};
};
var $elm$json$Json$Decode$Index = F2($elm$json$Json$Decode$Index$);
var $elm$core$Result$Ok = function (a) {
	return {$: 'Ok', a: a};
};
var $elm$json$Json$Decode$OneOf = function (a) {
	return {$: 'OneOf', a: a};
};
var $elm$core$Basics$False = {$: 'False'};
var $elm$core$Basics$add = _Basics_add;
var $elm$core$Maybe$Just = function (a) {
	return {$: 'Just', a: a};
};
var $elm$core$Maybe$Nothing = {$: 'Nothing'};
var $elm$core$String$all = _String_all;
var $elm$core$Basics$and = _Basics_and;
var $elm$core$Basics$append = _Utils_append;
var $elm$json$Json$Encode$encode = _Json_encode;
var $elm$core$String$fromInt = _String_fromNumber;
var $elm$core$String$join$ = function (sep, chunks) {
	return A2(
		_String_join,
		sep,
		_List_toArray(chunks));
};
var $elm$core$String$join = F2($elm$core$String$join$);
var $elm$core$String$split$ = function (sep, string) {
	return _List_fromArray(
		A2(_String_split, sep, string));
};
var $elm$core$String$split = F2($elm$core$String$split$);
var $elm$json$Json$Decode$indent = function (str) {
	return $elm$core$String$join$(
		'\n    ',
		$elm$core$String$split$('\n', str));
};
var $elm$core$List$foldl$ = function (func, acc, list) {
	foldl:
	while (true) {
		if (!list.b) {
			return acc;
		} else {
			var x = list.a;
			var xs = list.b;
			var $temp$acc = A2(func, x, acc),
				$temp$list = xs;
			acc = $temp$acc;
			list = $temp$list;
			continue foldl;
		}
	}
};
var $elm$core$List$foldl = F3($elm$core$List$foldl$);
var $elm$core$List$length = function (xs) {
	return $elm$core$List$foldl$(
		F2(
			function (_v0, i) {
				return i + 1;
			}),
		0,
		xs);
};
var $elm$core$List$map2 = _List_map2;
var $elm$core$Basics$le = _Utils_le;
var $elm$core$Basics$sub = _Basics_sub;
var $elm$core$List$rangeHelp$ = function (lo, hi, list) {
	rangeHelp:
	while (true) {
		if (_Utils_cmp(lo, hi) < 1) {
			var $temp$hi = hi - 1,
				$temp$list = A2($elm$core$List$cons, hi, list);
			hi = $temp$hi;
			list = $temp$list;
			continue rangeHelp;
		} else {
			return list;
		}
	}
};
var $elm$core$List$rangeHelp = F3($elm$core$List$rangeHelp$);
var $elm$core$List$range$ = function (lo, hi) {
	return $elm$core$List$rangeHelp$(lo, hi, _List_Nil);
};
var $elm$core$List$range = F2($elm$core$List$range$);
var $elm$core$List$indexedMap$ = function (f, xs) {
	return A3(
		$elm$core$List$map2,
		f,
		$elm$core$List$range$(
			0,
			$elm$core$List$length(xs) - 1),
		xs);
};
var $elm$core$List$indexedMap = F2($elm$core$List$indexedMap$);
var $elm$core$Char$toCode = _Char_toCode;
var $elm$core$Char$isLower = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (97 <= code) && (code <= 122);
};
var $elm$core$Char$isUpper = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 90) && (65 <= code);
};
var $elm$core$Basics$or = _Basics_or;
var $elm$core$Char$isAlpha = function (_char) {
	return $elm$core$Char$isLower(_char) || $elm$core$Char$isUpper(_char);
};
var $elm$core$Char$isDigit = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 57) && (48 <= code);
};
var $elm$core$Char$isAlphaNum = function (_char) {
	return $elm$core$Char$isLower(_char) || ($elm$core$Char$isUpper(_char) || $elm$core$Char$isDigit(_char));
};
var $elm$core$List$reverse = function (list) {
	return $elm$core$List$foldl$($elm$core$List$cons, _List_Nil, list);
};
var $elm$core$String$uncons = _String_uncons;
var $elm$json$Json$Decode$errorOneOf$ = function (i, error) {
	return '\n\n(' + ($elm$core$String$fromInt(i + 1) + (') ' + $elm$json$Json$Decode$indent(
		$elm$json$Json$Decode$errorToString(error))));
};
var $elm$json$Json$Decode$errorOneOf = F2($elm$json$Json$Decode$errorOneOf$);
var $elm$json$Json$Decode$errorToString = function (error) {
	return $elm$json$Json$Decode$errorToStringHelp$(error, _List_Nil);
};
var $elm$json$Json$Decode$errorToStringHelp$ = function (error, context) {
	errorToStringHelp:
	while (true) {
		switch (error.$) {
			case 'Field':
				var f = error.a;
				var err = error.b;
				var isSimple = function () {
					var _v1 = $elm$core$String$uncons(f);
					if (_v1.$ === 'Nothing') {
						return false;
					} else {
						var _v2 = _v1.a;
						var _char = _v2.a;
						var rest = _v2.b;
						return $elm$core$Char$isAlpha(_char) && A2($elm$core$String$all, $elm$core$Char$isAlphaNum, rest);
					}
				}();
				var fieldName = isSimple ? ('.' + f) : ('[\'' + (f + '\']'));
				var $temp$error = err,
					$temp$context = A2($elm$core$List$cons, fieldName, context);
				error = $temp$error;
				context = $temp$context;
				continue errorToStringHelp;
			case 'Index':
				var i = error.a;
				var err = error.b;
				var indexName = '[' + ($elm$core$String$fromInt(i) + ']');
				var $temp$error = err,
					$temp$context = A2($elm$core$List$cons, indexName, context);
				error = $temp$error;
				context = $temp$context;
				continue errorToStringHelp;
			case 'OneOf':
				var errors = error.a;
				if (!errors.b) {
					return 'Ran into a Json.Decode.oneOf with no possibilities' + function () {
						if (!context.b) {
							return '!';
						} else {
							return ' at json' + $elm$core$String$join$(
								'',
								$elm$core$List$reverse(context));
						}
					}();
				} else {
					if (!errors.b.b) {
						var err = errors.a;
						var $temp$error = err;
						error = $temp$error;
						continue errorToStringHelp;
					} else {
						var starter = function () {
							if (!context.b) {
								return 'Json.Decode.oneOf';
							} else {
								return 'The Json.Decode.oneOf at json' + $elm$core$String$join$(
									'',
									$elm$core$List$reverse(context));
							}
						}();
						var introduction = starter + (' failed in the following ' + ($elm$core$String$fromInt(
							$elm$core$List$length(errors)) + ' ways:'));
						return $elm$core$String$join$(
							'\n\n',
							A2(
								$elm$core$List$cons,
								introduction,
								$elm$core$List$indexedMap$($elm$json$Json$Decode$errorOneOf, errors)));
					}
				}
			default:
				var msg = error.a;
				var json = error.b;
				var introduction = function () {
					if (!context.b) {
						return 'Problem with the given value:\n\n';
					} else {
						return 'Problem with the value at json' + ($elm$core$String$join$(
							'',
							$elm$core$List$reverse(context)) + ':\n\n    ');
					}
				}();
				return introduction + ($elm$json$Json$Decode$indent(
					A2($elm$json$Json$Encode$encode, 4, json)) + ('\n\n' + msg));
		}
	}
};
var $elm$json$Json$Decode$errorToStringHelp = F2($elm$json$Json$Decode$errorToStringHelp$);
var $elm$core$Array$branchFactor = 32;
var $elm$core$Array$Array_elm_builtin$ = function (a, b, c, d) {
	return {$: 'Array_elm_builtin', a: a, b: b, c: c, d: d};
};
var $elm$core$Array$Array_elm_builtin = F4($elm$core$Array$Array_elm_builtin$);
var $elm$core$Elm$JsArray$empty = _JsArray_empty;
var $elm$core$Basics$ceiling = _Basics_ceiling;
var $elm$core$Basics$fdiv = _Basics_fdiv;
var $elm$core$Basics$logBase$ = function (base, number) {
	return _Basics_log(number) / _Basics_log(base);
};
var $elm$core$Basics$logBase = F2($elm$core$Basics$logBase$);
var $elm$core$Basics$toFloat = _Basics_toFloat;
var $elm$core$Array$shiftStep = $elm$core$Basics$ceiling(
	$elm$core$Basics$logBase$(2, $elm$core$Array$branchFactor));
var $elm$core$Array$empty = $elm$core$Array$Array_elm_builtin$(0, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, $elm$core$Elm$JsArray$empty);
var $elm$core$Elm$JsArray$initialize = _JsArray_initialize;
var $elm$core$Array$Leaf = function (a) {
	return {$: 'Leaf', a: a};
};
var $elm$core$Basics$apL$ = function (f, x) {
	return f(x);
};
var $elm$core$Basics$apL = F2($elm$core$Basics$apL$);
var $elm$core$Basics$apR$ = function (x, f) {
	return f(x);
};
var $elm$core$Basics$apR = F2($elm$core$Basics$apR$);
var $elm$core$Basics$eq = _Utils_equal;
var $elm$core$Basics$floor = _Basics_floor;
var $elm$core$Elm$JsArray$length = _JsArray_length;
var $elm$core$Basics$gt = _Utils_gt;
var $elm$core$Basics$max$ = function (x, y) {
	return (_Utils_cmp(x, y) > 0) ? x : y;
};
var $elm$core$Basics$max = F2($elm$core$Basics$max$);
var $elm$core$Basics$mul = _Basics_mul;
var $elm$core$Array$SubTree = function (a) {
	return {$: 'SubTree', a: a};
};
var $elm$core$Elm$JsArray$initializeFromList = _JsArray_initializeFromList;
var $elm$core$Array$compressNodes$ = function (nodes, acc) {
	compressNodes:
	while (true) {
		var _v0 = A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodes);
		var node = _v0.a;
		var remainingNodes = _v0.b;
		var newAcc = A2(
			$elm$core$List$cons,
			$elm$core$Array$SubTree(node),
			acc);
		if (!remainingNodes.b) {
			return $elm$core$List$reverse(newAcc);
		} else {
			var $temp$nodes = remainingNodes,
				$temp$acc = newAcc;
			nodes = $temp$nodes;
			acc = $temp$acc;
			continue compressNodes;
		}
	}
};
var $elm$core$Array$compressNodes = F2($elm$core$Array$compressNodes$);
var $elm$core$Tuple$first = function (_v0) {
	var x = _v0.a;
	return x;
};
var $elm$core$Array$treeFromBuilder$ = function (nodeList, nodeListSize) {
	treeFromBuilder:
	while (true) {
		var newNodeSize = $elm$core$Basics$ceiling(nodeListSize / $elm$core$Array$branchFactor);
		if (newNodeSize === 1) {
			return A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodeList).a;
		} else {
			var $temp$nodeList = $elm$core$Array$compressNodes$(nodeList, _List_Nil),
				$temp$nodeListSize = newNodeSize;
			nodeList = $temp$nodeList;
			nodeListSize = $temp$nodeListSize;
			continue treeFromBuilder;
		}
	}
};
var $elm$core$Array$treeFromBuilder = F2($elm$core$Array$treeFromBuilder$);
var $elm$core$Array$builderToArray$ = function (reverseNodeList, builder) {
	if (!builder.nodeListSize) {
		return $elm$core$Array$Array_elm_builtin$(
			$elm$core$Elm$JsArray$length(builder.tail),
			$elm$core$Array$shiftStep,
			$elm$core$Elm$JsArray$empty,
			builder.tail);
	} else {
		var treeLen = builder.nodeListSize * $elm$core$Array$branchFactor;
		var depth = $elm$core$Basics$floor(
			$elm$core$Basics$logBase$($elm$core$Array$branchFactor, treeLen - 1));
		var correctNodeList = reverseNodeList ? $elm$core$List$reverse(builder.nodeList) : builder.nodeList;
		var tree = $elm$core$Array$treeFromBuilder$(correctNodeList, builder.nodeListSize);
		return $elm$core$Array$Array_elm_builtin$(
			$elm$core$Elm$JsArray$length(builder.tail) + treeLen,
			$elm$core$Basics$max$(5, depth * $elm$core$Array$shiftStep),
			tree,
			builder.tail);
	}
};
var $elm$core$Array$builderToArray = F2($elm$core$Array$builderToArray$);
var $elm$core$Basics$idiv = _Basics_idiv;
var $elm$core$Basics$lt = _Utils_lt;
var $elm$core$Array$initializeHelp$ = function (fn, fromIndex, len, nodeList, tail) {
	initializeHelp:
	while (true) {
		if (fromIndex < 0) {
			return $elm$core$Array$builderToArray$(
				false,
				{nodeList: nodeList, nodeListSize: (len / $elm$core$Array$branchFactor) | 0, tail: tail});
		} else {
			var leaf = $elm$core$Array$Leaf(
				A3($elm$core$Elm$JsArray$initialize, $elm$core$Array$branchFactor, fromIndex, fn));
			var $temp$fromIndex = fromIndex - $elm$core$Array$branchFactor,
				$temp$nodeList = A2($elm$core$List$cons, leaf, nodeList);
			fromIndex = $temp$fromIndex;
			nodeList = $temp$nodeList;
			continue initializeHelp;
		}
	}
};
var $elm$core$Array$initializeHelp = F5($elm$core$Array$initializeHelp$);
var $elm$core$Basics$remainderBy = _Basics_remainderBy;
var $elm$core$Array$initialize$ = function (len, fn) {
	if (len <= 0) {
		return $elm$core$Array$empty;
	} else {
		var tailLen = len % $elm$core$Array$branchFactor;
		var tail = A3($elm$core$Elm$JsArray$initialize, tailLen, len - tailLen, fn);
		var initialFromIndex = (len - tailLen) - $elm$core$Array$branchFactor;
		return $elm$core$Array$initializeHelp$(fn, initialFromIndex, len, _List_Nil, tail);
	}
};
var $elm$core$Array$initialize = F2($elm$core$Array$initialize$);
var $elm$core$Basics$True = {$: 'True'};
var $elm$core$Result$isOk = function (result) {
	if (result.$ === 'Ok') {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function (handler) {
	switch (handler.$) {
		case 'Normal':
			return 0;
		case 'MayStopPropagation':
			return 1;
		case 'MayPreventDefault':
			return 2;
		default:
			return 3;
	}
};
var $elm$browser$Browser$External = function (a) {
	return {$: 'External', a: a};
};
var $elm$browser$Browser$Internal = function (a) {
	return {$: 'Internal', a: a};
};
var $elm$core$Basics$identity = function (x) {
	return x;
};
var $elm$browser$Browser$Dom$NotFound = function (a) {
	return {$: 'NotFound', a: a};
};
var $elm$url$Url$Http = {$: 'Http'};
var $elm$url$Url$Https = {$: 'Https'};
var $elm$url$Url$Url$ = function (protocol, host, port_, path, query, fragment) {
	return {fragment: fragment, host: host, path: path, port_: port_, protocol: protocol, query: query};
};
var $elm$url$Url$Url = F6($elm$url$Url$Url$);
var $elm$core$String$contains = _String_contains;
var $elm$core$String$length = _String_length;
var $elm$core$String$slice = _String_slice;
var $elm$core$String$dropLeft$ = function (n, string) {
	return (n < 1) ? string : A3(
		$elm$core$String$slice,
		n,
		$elm$core$String$length(string),
		string);
};
var $elm$core$String$dropLeft = F2($elm$core$String$dropLeft$);
var $elm$core$String$indexes = _String_indexes;
var $elm$core$String$isEmpty = function (string) {
	return string === '';
};
var $elm$core$String$left$ = function (n, string) {
	return (n < 1) ? '' : A3($elm$core$String$slice, 0, n, string);
};
var $elm$core$String$left = F2($elm$core$String$left$);
var $elm$core$String$toInt = _String_toInt;
var $elm$url$Url$chompBeforePath$ = function (protocol, path, params, frag, str) {
	if ($elm$core$String$isEmpty(str) || A2($elm$core$String$contains, '@', str)) {
		return $elm$core$Maybe$Nothing;
	} else {
		var _v0 = A2($elm$core$String$indexes, ':', str);
		if (!_v0.b) {
			return $elm$core$Maybe$Just(
				$elm$url$Url$Url$(protocol, str, $elm$core$Maybe$Nothing, path, params, frag));
		} else {
			if (!_v0.b.b) {
				var i = _v0.a;
				var _v1 = $elm$core$String$toInt(
					$elm$core$String$dropLeft$(i + 1, str));
				if (_v1.$ === 'Nothing') {
					return $elm$core$Maybe$Nothing;
				} else {
					var port_ = _v1;
					return $elm$core$Maybe$Just(
						$elm$url$Url$Url$(
							protocol,
							$elm$core$String$left$(i, str),
							port_,
							path,
							params,
							frag));
				}
			} else {
				return $elm$core$Maybe$Nothing;
			}
		}
	}
};
var $elm$url$Url$chompBeforePath = F5($elm$url$Url$chompBeforePath$);
var $elm$url$Url$chompBeforeQuery$ = function (protocol, params, frag, str) {
	if ($elm$core$String$isEmpty(str)) {
		return $elm$core$Maybe$Nothing;
	} else {
		var _v0 = A2($elm$core$String$indexes, '/', str);
		if (!_v0.b) {
			return $elm$url$Url$chompBeforePath$(protocol, '/', params, frag, str);
		} else {
			var i = _v0.a;
			return $elm$url$Url$chompBeforePath$(
				protocol,
				$elm$core$String$dropLeft$(i, str),
				params,
				frag,
				$elm$core$String$left$(i, str));
		}
	}
};
var $elm$url$Url$chompBeforeQuery = F4($elm$url$Url$chompBeforeQuery$);
var $elm$url$Url$chompBeforeFragment$ = function (protocol, frag, str) {
	if ($elm$core$String$isEmpty(str)) {
		return $elm$core$Maybe$Nothing;
	} else {
		var _v0 = A2($elm$core$String$indexes, '?', str);
		if (!_v0.b) {
			return $elm$url$Url$chompBeforeQuery$(protocol, $elm$core$Maybe$Nothing, frag, str);
		} else {
			var i = _v0.a;
			return $elm$url$Url$chompBeforeQuery$(
				protocol,
				$elm$core$Maybe$Just(
					$elm$core$String$dropLeft$(i + 1, str)),
				frag,
				$elm$core$String$left$(i, str));
		}
	}
};
var $elm$url$Url$chompBeforeFragment = F3($elm$url$Url$chompBeforeFragment$);
var $elm$url$Url$chompAfterProtocol$ = function (protocol, str) {
	if ($elm$core$String$isEmpty(str)) {
		return $elm$core$Maybe$Nothing;
	} else {
		var _v0 = A2($elm$core$String$indexes, '#', str);
		if (!_v0.b) {
			return $elm$url$Url$chompBeforeFragment$(protocol, $elm$core$Maybe$Nothing, str);
		} else {
			var i = _v0.a;
			return $elm$url$Url$chompBeforeFragment$(
				protocol,
				$elm$core$Maybe$Just(
					$elm$core$String$dropLeft$(i + 1, str)),
				$elm$core$String$left$(i, str));
		}
	}
};
var $elm$url$Url$chompAfterProtocol = F2($elm$url$Url$chompAfterProtocol$);
var $elm$core$String$startsWith = _String_startsWith;
var $elm$url$Url$fromString = function (str) {
	return A2($elm$core$String$startsWith, 'http://', str) ? $elm$url$Url$chompAfterProtocol$(
		$elm$url$Url$Http,
		$elm$core$String$dropLeft$(7, str)) : (A2($elm$core$String$startsWith, 'https://', str) ? $elm$url$Url$chompAfterProtocol$(
		$elm$url$Url$Https,
		$elm$core$String$dropLeft$(8, str)) : $elm$core$Maybe$Nothing);
};
var $elm$core$Basics$never = function (_v0) {
	never:
	while (true) {
		var nvr = _v0.a;
		var $temp$_v0 = nvr;
		_v0 = $temp$_v0;
		continue never;
	}
};
var $elm$core$Task$Perform = function (a) {
	return {$: 'Perform', a: a};
};
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed(_Utils_Tuple0);
var $elm$core$List$foldrHelper$ = function (fn, acc, ctr, ls) {
	if (!ls.b) {
		return acc;
	} else {
		var a = ls.a;
		var r1 = ls.b;
		if (!r1.b) {
			return A2(fn, a, acc);
		} else {
			var b = r1.a;
			var r2 = r1.b;
			if (!r2.b) {
				return A2(
					fn,
					a,
					A2(fn, b, acc));
			} else {
				var c = r2.a;
				var r3 = r2.b;
				if (!r3.b) {
					return A2(
						fn,
						a,
						A2(
							fn,
							b,
							A2(fn, c, acc)));
				} else {
					var d = r3.a;
					var r4 = r3.b;
					var res = (ctr > 500) ? $elm$core$List$foldl$(
						fn,
						acc,
						$elm$core$List$reverse(r4)) : $elm$core$List$foldrHelper$(fn, acc, ctr + 1, r4);
					return A2(
						fn,
						a,
						A2(
							fn,
							b,
							A2(
								fn,
								c,
								A2(fn, d, res))));
				}
			}
		}
	}
};
var $elm$core$List$foldrHelper = F4($elm$core$List$foldrHelper$);
var $elm$core$List$foldr$ = function (fn, acc, ls) {
	return $elm$core$List$foldrHelper$(fn, acc, 0, ls);
};
var $elm$core$List$foldr = F3($elm$core$List$foldr$);
var $elm$core$List$map$ = function (f, xs) {
	return $elm$core$List$foldr$(
		F2(
			function (x, acc) {
				return A2(
					$elm$core$List$cons,
					f(x),
					acc);
			}),
		_List_Nil,
		xs);
};
var $elm$core$List$map = F2($elm$core$List$map$);
var $elm$core$Task$andThen = _Scheduler_andThen;
var $elm$core$Task$map$ = function (func, taskA) {
	return A2(
		$elm$core$Task$andThen,
		function (a) {
			return $elm$core$Task$succeed(
				func(a));
		},
		taskA);
};
var $elm$core$Task$map = F2($elm$core$Task$map$);
var $elm$core$Task$map2$ = function (func, taskA, taskB) {
	return A2(
		$elm$core$Task$andThen,
		function (a) {
			return A2(
				$elm$core$Task$andThen,
				function (b) {
					return $elm$core$Task$succeed(
						A2(func, a, b));
				},
				taskB);
		},
		taskA);
};
var $elm$core$Task$map2 = F3($elm$core$Task$map2$);
var $elm$core$Task$sequence = function (tasks) {
	return $elm$core$List$foldr$(
		$elm$core$Task$map2($elm$core$List$cons),
		$elm$core$Task$succeed(_List_Nil),
		tasks);
};
var $elm$core$Platform$sendToApp = _Platform_sendToApp;
var $elm$core$Task$spawnCmd$ = function (router, _v0) {
	var task = _v0.a;
	return _Scheduler_spawn(
		A2(
			$elm$core$Task$andThen,
			$elm$core$Platform$sendToApp(router),
			task));
};
var $elm$core$Task$spawnCmd = F2($elm$core$Task$spawnCmd$);
var $elm$core$Task$onEffects$ = function (router, commands, state) {
	return $elm$core$Task$map$(
		function (_v0) {
			return _Utils_Tuple0;
		},
		$elm$core$Task$sequence(
			$elm$core$List$map$(
				$elm$core$Task$spawnCmd(router),
				commands)));
};
var $elm$core$Task$onEffects = F3($elm$core$Task$onEffects$);
var $elm$core$Task$onSelfMsg$ = function (_v0, _v1, _v2) {
	return $elm$core$Task$succeed(_Utils_Tuple0);
};
var $elm$core$Task$onSelfMsg = F3($elm$core$Task$onSelfMsg$);
var $elm$core$Task$cmdMap$ = function (tagger, _v0) {
	var task = _v0.a;
	return $elm$core$Task$Perform(
		$elm$core$Task$map$(tagger, task));
};
var $elm$core$Task$cmdMap = F2($elm$core$Task$cmdMap$);
_Platform_effectManagers['Task'] = _Platform_createManager($elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap);
var $elm$core$Task$command = _Platform_leaf('Task');
var $elm$core$Task$perform$ = function (toMessage, task) {
	return $elm$core$Task$command(
		$elm$core$Task$Perform(
			$elm$core$Task$map$(toMessage, task)));
};
var $elm$core$Task$perform = F2($elm$core$Task$perform$);
var $elm$browser$Browser$element = _Browser_element;
var $elm$time$Time$Every$ = function (a, b) {
	return {$: 'Every', a: a, b: b};
};
var $elm$time$Time$Every = F2($elm$time$Time$Every$);
var $elm$time$Time$State$ = function (taggers, processes) {
	return {processes: processes, taggers: taggers};
};
var $elm$time$Time$State = F2($elm$time$Time$State$);
var $elm$core$Dict$RBEmpty_elm_builtin = {$: 'RBEmpty_elm_builtin'};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$time$Time$init = $elm$core$Task$succeed(
	$elm$time$Time$State$($elm$core$Dict$empty, $elm$core$Dict$empty));
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$get$ = function (targetKey, dict) {
	get:
	while (true) {
		if (dict.$ === 'RBEmpty_elm_builtin') {
			return $elm$core$Maybe$Nothing;
		} else {
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			var _v1 = A2($elm$core$Basics$compare, targetKey, key);
			switch (_v1.$) {
				case 'LT':
					var $temp$dict = left;
					dict = $temp$dict;
					continue get;
				case 'EQ':
					return $elm$core$Maybe$Just(value);
				default:
					var $temp$dict = right;
					dict = $temp$dict;
					continue get;
			}
		}
	}
};
var $elm$core$Dict$get = F2($elm$core$Dict$get$);
var $elm$core$Dict$Black = {$: 'Black'};
var $elm$core$Dict$RBNode_elm_builtin$ = function (a, b, c, d, e) {
	return {$: 'RBNode_elm_builtin', a: a, b: b, c: c, d: d, e: e};
};
var $elm$core$Dict$RBNode_elm_builtin = F5($elm$core$Dict$RBNode_elm_builtin$);
var $elm$core$Dict$Red = {$: 'Red'};
var $elm$core$Dict$balance$ = function (color, key, value, left, right) {
	if ((right.$ === 'RBNode_elm_builtin') && (right.a.$ === 'Red')) {
		var _v1 = right.a;
		var rK = right.b;
		var rV = right.c;
		var rLeft = right.d;
		var rRight = right.e;
		if ((left.$ === 'RBNode_elm_builtin') && (left.a.$ === 'Red')) {
			var _v3 = left.a;
			var lK = left.b;
			var lV = left.c;
			var lLeft = left.d;
			var lRight = left.e;
			return $elm$core$Dict$RBNode_elm_builtin$(
				$elm$core$Dict$Red,
				key,
				value,
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, lK, lV, lLeft, lRight),
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, rK, rV, rLeft, rRight));
		} else {
			return $elm$core$Dict$RBNode_elm_builtin$(
				color,
				rK,
				rV,
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, key, value, left, rLeft),
				rRight);
		}
	} else {
		if ((((left.$ === 'RBNode_elm_builtin') && (left.a.$ === 'Red')) && (left.d.$ === 'RBNode_elm_builtin')) && (left.d.a.$ === 'Red')) {
			var _v5 = left.a;
			var lK = left.b;
			var lV = left.c;
			var _v6 = left.d;
			var _v7 = _v6.a;
			var llK = _v6.b;
			var llV = _v6.c;
			var llLeft = _v6.d;
			var llRight = _v6.e;
			var lRight = left.e;
			return $elm$core$Dict$RBNode_elm_builtin$(
				$elm$core$Dict$Red,
				lK,
				lV,
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, llK, llV, llLeft, llRight),
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, key, value, lRight, right));
		} else {
			return $elm$core$Dict$RBNode_elm_builtin$(color, key, value, left, right);
		}
	}
};
var $elm$core$Dict$balance = F5($elm$core$Dict$balance$);
var $elm$core$Dict$insertHelp$ = function (key, value, dict) {
	if (dict.$ === 'RBEmpty_elm_builtin') {
		return $elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
	} else {
		var nColor = dict.a;
		var nKey = dict.b;
		var nValue = dict.c;
		var nLeft = dict.d;
		var nRight = dict.e;
		var _v1 = A2($elm$core$Basics$compare, key, nKey);
		switch (_v1.$) {
			case 'LT':
				return $elm$core$Dict$balance$(
					nColor,
					nKey,
					nValue,
					$elm$core$Dict$insertHelp$(key, value, nLeft),
					nRight);
			case 'EQ':
				return $elm$core$Dict$RBNode_elm_builtin$(nColor, nKey, value, nLeft, nRight);
			default:
				return $elm$core$Dict$balance$(
					nColor,
					nKey,
					nValue,
					nLeft,
					$elm$core$Dict$insertHelp$(key, value, nRight));
		}
	}
};
var $elm$core$Dict$insertHelp = F3($elm$core$Dict$insertHelp$);
var $elm$core$Dict$insert$ = function (key, value, dict) {
	var _v0 = $elm$core$Dict$insertHelp$(key, value, dict);
	if ((_v0.$ === 'RBNode_elm_builtin') && (_v0.a.$ === 'Red')) {
		var _v1 = _v0.a;
		var k = _v0.b;
		var v = _v0.c;
		var l = _v0.d;
		var r = _v0.e;
		return $elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, k, v, l, r);
	} else {
		var x = _v0;
		return x;
	}
};
var $elm$core$Dict$insert = F3($elm$core$Dict$insert$);
var $elm$time$Time$addMySub$ = function (_v0, state) {
	var interval = _v0.a;
	var tagger = _v0.b;
	var _v1 = $elm$core$Dict$get$(interval, state);
	if (_v1.$ === 'Nothing') {
		return $elm$core$Dict$insert$(
			interval,
			_List_fromArray(
				[tagger]),
			state);
	} else {
		var taggers = _v1.a;
		return $elm$core$Dict$insert$(
			interval,
			A2($elm$core$List$cons, tagger, taggers),
			state);
	}
};
var $elm$time$Time$addMySub = F2($elm$time$Time$addMySub$);
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$core$Dict$foldl$ = function (func, acc, dict) {
	foldl:
	while (true) {
		if (dict.$ === 'RBEmpty_elm_builtin') {
			return acc;
		} else {
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			var $temp$acc = A3(
				func,
				key,
				value,
				$elm$core$Dict$foldl$(func, acc, left)),
				$temp$dict = right;
			acc = $temp$acc;
			dict = $temp$dict;
			continue foldl;
		}
	}
};
var $elm$core$Dict$foldl = F3($elm$core$Dict$foldl$);
var $elm$core$Dict$merge$ = function (leftStep, bothStep, rightStep, leftDict, rightDict, initialResult) {
	var stepState = F3(
		function (rKey, rValue, _v0) {
			stepState:
			while (true) {
				var list = _v0.a;
				var result = _v0.b;
				if (!list.b) {
					return _Utils_Tuple2(
						list,
						A3(rightStep, rKey, rValue, result));
				} else {
					var _v2 = list.a;
					var lKey = _v2.a;
					var lValue = _v2.b;
					var rest = list.b;
					if (_Utils_cmp(lKey, rKey) < 0) {
						var $temp$_v0 = _Utils_Tuple2(
							rest,
							A3(leftStep, lKey, lValue, result));
						_v0 = $temp$_v0;
						continue stepState;
					} else {
						if (_Utils_cmp(lKey, rKey) > 0) {
							return _Utils_Tuple2(
								list,
								A3(rightStep, rKey, rValue, result));
						} else {
							return _Utils_Tuple2(
								rest,
								A4(bothStep, lKey, lValue, rValue, result));
						}
					}
				}
			}
		});
	var _v3 = $elm$core$Dict$foldl$(
		stepState,
		_Utils_Tuple2(
			$elm$core$Dict$toList(leftDict),
			initialResult),
		rightDict);
	var leftovers = _v3.a;
	var intermediateResult = _v3.b;
	return $elm$core$List$foldl$(
		F2(
			function (_v4, result) {
				var k = _v4.a;
				var v = _v4.b;
				return A3(leftStep, k, v, result);
			}),
		intermediateResult,
		leftovers);
};
var $elm$core$Dict$merge = F6($elm$core$Dict$merge$);
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$time$Time$Name = function (a) {
	return {$: 'Name', a: a};
};
var $elm$time$Time$Offset = function (a) {
	return {$: 'Offset', a: a};
};
var $elm$time$Time$Zone$ = function (a, b) {
	return {$: 'Zone', a: a, b: b};
};
var $elm$time$Time$Zone = F2($elm$time$Time$Zone$);
var $elm$time$Time$customZone = $elm$time$Time$Zone;
var $elm$time$Time$setInterval = _Time_setInterval;
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$time$Time$spawnHelp$ = function (router, intervals, processes) {
	if (!intervals.b) {
		return $elm$core$Task$succeed(processes);
	} else {
		var interval = intervals.a;
		var rest = intervals.b;
		var spawnTimer = $elm$core$Process$spawn(
			A2(
				$elm$time$Time$setInterval,
				interval,
				A2($elm$core$Platform$sendToSelf, router, interval)));
		var spawnRest = function (id) {
			return $elm$time$Time$spawnHelp$(
				router,
				rest,
				$elm$core$Dict$insert$(interval, id, processes));
		};
		return A2($elm$core$Task$andThen, spawnRest, spawnTimer);
	}
};
var $elm$time$Time$spawnHelp = F3($elm$time$Time$spawnHelp$);
var $elm$time$Time$onEffects$ = function (router, subs, _v0) {
	var processes = _v0.processes;
	var rightStep = F3(
		function (_v6, id, _v7) {
			var spawns = _v7.a;
			var existing = _v7.b;
			var kills = _v7.c;
			return _Utils_Tuple3(
				spawns,
				existing,
				A2(
					$elm$core$Task$andThen,
					function (_v5) {
						return kills;
					},
					$elm$core$Process$kill(id)));
		});
	var newTaggers = $elm$core$List$foldl$($elm$time$Time$addMySub, $elm$core$Dict$empty, subs);
	var leftStep = F3(
		function (interval, taggers, _v4) {
			var spawns = _v4.a;
			var existing = _v4.b;
			var kills = _v4.c;
			return _Utils_Tuple3(
				A2($elm$core$List$cons, interval, spawns),
				existing,
				kills);
		});
	var bothStep = F4(
		function (interval, taggers, id, _v3) {
			var spawns = _v3.a;
			var existing = _v3.b;
			var kills = _v3.c;
			return _Utils_Tuple3(
				spawns,
				$elm$core$Dict$insert$(interval, id, existing),
				kills);
		});
	var _v1 = $elm$core$Dict$merge$(
		leftStep,
		bothStep,
		rightStep,
		newTaggers,
		processes,
		_Utils_Tuple3(
			_List_Nil,
			$elm$core$Dict$empty,
			$elm$core$Task$succeed(_Utils_Tuple0)));
	var spawnList = _v1.a;
	var existingDict = _v1.b;
	var killTask = _v1.c;
	return A2(
		$elm$core$Task$andThen,
		function (newProcesses) {
			return $elm$core$Task$succeed(
				$elm$time$Time$State$(newTaggers, newProcesses));
		},
		A2(
			$elm$core$Task$andThen,
			function (_v2) {
				return $elm$time$Time$spawnHelp$(router, spawnList, existingDict);
			},
			killTask));
};
var $elm$time$Time$onEffects = F3($elm$time$Time$onEffects$);
var $elm$time$Time$Posix = function (a) {
	return {$: 'Posix', a: a};
};
var $elm$time$Time$millisToPosix = $elm$time$Time$Posix;
var $elm$time$Time$now = _Time_now($elm$time$Time$millisToPosix);
var $elm$time$Time$onSelfMsg$ = function (router, interval, state) {
	var _v0 = $elm$core$Dict$get$(interval, state.taggers);
	if (_v0.$ === 'Nothing') {
		return $elm$core$Task$succeed(state);
	} else {
		var taggers = _v0.a;
		var tellTaggers = function (time) {
			return $elm$core$Task$sequence(
				$elm$core$List$map$(
					function (tagger) {
						return A2(
							$elm$core$Platform$sendToApp,
							router,
							tagger(time));
					},
					taggers));
		};
		return A2(
			$elm$core$Task$andThen,
			function (_v1) {
				return $elm$core$Task$succeed(state);
			},
			A2($elm$core$Task$andThen, tellTaggers, $elm$time$Time$now));
	}
};
var $elm$time$Time$onSelfMsg = F3($elm$time$Time$onSelfMsg$);
var $elm$core$Basics$composeL$ = function (g, f, x) {
	return g(
		f(x));
};
var $elm$core$Basics$composeL = F3($elm$core$Basics$composeL$);
var $elm$time$Time$subMap$ = function (f, _v0) {
	var interval = _v0.a;
	var tagger = _v0.b;
	return $elm$time$Time$Every$(
		interval,
		A2($elm$core$Basics$composeL, f, tagger));
};
var $elm$time$Time$subMap = F2($elm$time$Time$subMap$);
_Platform_effectManagers['Time'] = _Platform_createManager($elm$time$Time$init, $elm$time$Time$onEffects, $elm$time$Time$onSelfMsg, 0, $elm$time$Time$subMap);
var $elm$time$Time$subscription = _Platform_leaf('Time');
var $elm$time$Time$every$ = function (interval, tagger) {
	return $elm$time$Time$subscription(
		$elm$time$Time$Every$(interval, tagger));
};
var $elm$time$Time$every = F2($elm$time$Time$every$);
var $author$project$Neat$Dashboard$Got = function (a) {
	return {$: 'Got', a: a};
};
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
var $elm$http$Http$BadStatus_$ = function (a, b) {
	return {$: 'BadStatus_', a: a, b: b};
};
var $elm$http$Http$BadStatus_ = F2($elm$http$Http$BadStatus_$);
var $elm$http$Http$BadUrl_ = function (a) {
	return {$: 'BadUrl_', a: a};
};
var $elm$http$Http$GoodStatus_$ = function (a, b) {
	return {$: 'GoodStatus_', a: a, b: b};
};
var $elm$http$Http$GoodStatus_ = F2($elm$http$Http$GoodStatus_$);
var $elm$http$Http$NetworkError_ = {$: 'NetworkError_'};
var $elm$http$Http$Receiving = function (a) {
	return {$: 'Receiving', a: a};
};
var $elm$http$Http$Sending = function (a) {
	return {$: 'Sending', a: a};
};
var $elm$http$Http$Timeout_ = {$: 'Timeout_'};
var $elm$core$Maybe$isJust = function (maybe) {
	if (maybe.$ === 'Just') {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Dict$getMin = function (dict) {
	getMin:
	while (true) {
		if ((dict.$ === 'RBNode_elm_builtin') && (dict.d.$ === 'RBNode_elm_builtin')) {
			var left = dict.d;
			var $temp$dict = left;
			dict = $temp$dict;
			continue getMin;
		} else {
			return dict;
		}
	}
};
var $elm$core$Dict$moveRedLeft = function (dict) {
	if (((dict.$ === 'RBNode_elm_builtin') && (dict.d.$ === 'RBNode_elm_builtin')) && (dict.e.$ === 'RBNode_elm_builtin')) {
		if ((dict.e.d.$ === 'RBNode_elm_builtin') && (dict.e.d.a.$ === 'Red')) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var lLeft = _v1.d;
			var lRight = _v1.e;
			var _v2 = dict.e;
			var rClr = _v2.a;
			var rK = _v2.b;
			var rV = _v2.c;
			var rLeft = _v2.d;
			var _v3 = rLeft.a;
			var rlK = rLeft.b;
			var rlV = rLeft.c;
			var rlL = rLeft.d;
			var rlR = rLeft.e;
			var rRight = _v2.e;
			return $elm$core$Dict$RBNode_elm_builtin$(
				$elm$core$Dict$Red,
				rlK,
				rlV,
				$elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, lK, lV, lLeft, lRight),
					rlL),
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, rK, rV, rlR, rRight));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v4 = dict.d;
			var lClr = _v4.a;
			var lK = _v4.b;
			var lV = _v4.c;
			var lLeft = _v4.d;
			var lRight = _v4.e;
			var _v5 = dict.e;
			var rClr = _v5.a;
			var rK = _v5.b;
			var rV = _v5.c;
			var rLeft = _v5.d;
			var rRight = _v5.e;
			if (clr.$ === 'Black') {
				return $elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, rK, rV, rLeft, rRight));
			} else {
				return $elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$moveRedRight = function (dict) {
	if (((dict.$ === 'RBNode_elm_builtin') && (dict.d.$ === 'RBNode_elm_builtin')) && (dict.e.$ === 'RBNode_elm_builtin')) {
		if ((dict.d.d.$ === 'RBNode_elm_builtin') && (dict.d.d.a.$ === 'Red')) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var _v2 = _v1.d;
			var _v3 = _v2.a;
			var llK = _v2.b;
			var llV = _v2.c;
			var llLeft = _v2.d;
			var llRight = _v2.e;
			var lRight = _v1.e;
			var _v4 = dict.e;
			var rClr = _v4.a;
			var rK = _v4.b;
			var rV = _v4.c;
			var rLeft = _v4.d;
			var rRight = _v4.e;
			return $elm$core$Dict$RBNode_elm_builtin$(
				$elm$core$Dict$Red,
				lK,
				lV,
				$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, llK, llV, llLeft, llRight),
				$elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					lRight,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, rK, rV, rLeft, rRight)));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v5 = dict.d;
			var lClr = _v5.a;
			var lK = _v5.b;
			var lV = _v5.c;
			var lLeft = _v5.d;
			var lRight = _v5.e;
			var _v6 = dict.e;
			var rClr = _v6.a;
			var rK = _v6.b;
			var rV = _v6.c;
			var rLeft = _v6.d;
			var rRight = _v6.e;
			if (clr.$ === 'Black') {
				return $elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, rK, rV, rLeft, rRight));
			} else {
				return $elm$core$Dict$RBNode_elm_builtin$(
					$elm$core$Dict$Black,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT$ = function (targetKey, dict, color, key, value, left, right) {
	if ((left.$ === 'RBNode_elm_builtin') && (left.a.$ === 'Red')) {
		var _v1 = left.a;
		var lK = left.b;
		var lV = left.c;
		var lLeft = left.d;
		var lRight = left.e;
		return $elm$core$Dict$RBNode_elm_builtin$(
			color,
			lK,
			lV,
			lLeft,
			$elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Red, key, value, lRight, right));
	} else {
		_v2$2:
		while (true) {
			if ((right.$ === 'RBNode_elm_builtin') && (right.a.$ === 'Black')) {
				if (right.d.$ === 'RBNode_elm_builtin') {
					if (right.d.a.$ === 'Black') {
						var _v3 = right.a;
						var _v4 = right.d;
						var _v5 = _v4.a;
						return $elm$core$Dict$moveRedRight(dict);
					} else {
						break _v2$2;
					}
				} else {
					var _v6 = right.a;
					var _v7 = right.d;
					return $elm$core$Dict$moveRedRight(dict);
				}
			} else {
				break _v2$2;
			}
		}
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT = F7($elm$core$Dict$removeHelpPrepEQGT$);
var $elm$core$Dict$removeMin = function (dict) {
	if ((dict.$ === 'RBNode_elm_builtin') && (dict.d.$ === 'RBNode_elm_builtin')) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var lColor = left.a;
		var lLeft = left.d;
		var right = dict.e;
		if (lColor.$ === 'Black') {
			if ((lLeft.$ === 'RBNode_elm_builtin') && (lLeft.a.$ === 'Red')) {
				var _v3 = lLeft.a;
				return $elm$core$Dict$RBNode_elm_builtin$(
					color,
					key,
					value,
					$elm$core$Dict$removeMin(left),
					right);
			} else {
				var _v4 = $elm$core$Dict$moveRedLeft(dict);
				if (_v4.$ === 'RBNode_elm_builtin') {
					var nColor = _v4.a;
					var nKey = _v4.b;
					var nValue = _v4.c;
					var nLeft = _v4.d;
					var nRight = _v4.e;
					return $elm$core$Dict$balance$(
						nColor,
						nKey,
						nValue,
						$elm$core$Dict$removeMin(nLeft),
						nRight);
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			}
		} else {
			return $elm$core$Dict$RBNode_elm_builtin$(
				color,
				key,
				value,
				$elm$core$Dict$removeMin(left),
				right);
		}
	} else {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	}
};
var $elm$core$Dict$removeHelp$ = function (targetKey, dict) {
	if (dict.$ === 'RBEmpty_elm_builtin') {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	} else {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var right = dict.e;
		if (_Utils_cmp(targetKey, key) < 0) {
			if ((left.$ === 'RBNode_elm_builtin') && (left.a.$ === 'Black')) {
				var _v4 = left.a;
				var lLeft = left.d;
				if ((lLeft.$ === 'RBNode_elm_builtin') && (lLeft.a.$ === 'Red')) {
					var _v6 = lLeft.a;
					return $elm$core$Dict$RBNode_elm_builtin$(
						color,
						key,
						value,
						$elm$core$Dict$removeHelp$(targetKey, left),
						right);
				} else {
					var _v7 = $elm$core$Dict$moveRedLeft(dict);
					if (_v7.$ === 'RBNode_elm_builtin') {
						var nColor = _v7.a;
						var nKey = _v7.b;
						var nValue = _v7.c;
						var nLeft = _v7.d;
						var nRight = _v7.e;
						return $elm$core$Dict$balance$(
							nColor,
							nKey,
							nValue,
							$elm$core$Dict$removeHelp$(targetKey, nLeft),
							nRight);
					} else {
						return $elm$core$Dict$RBEmpty_elm_builtin;
					}
				}
			} else {
				return $elm$core$Dict$RBNode_elm_builtin$(
					color,
					key,
					value,
					$elm$core$Dict$removeHelp$(targetKey, left),
					right);
			}
		} else {
			return $elm$core$Dict$removeHelpEQGT$(
				targetKey,
				$elm$core$Dict$removeHelpPrepEQGT$(targetKey, dict, color, key, value, left, right));
		}
	}
};
var $elm$core$Dict$removeHelp = F2($elm$core$Dict$removeHelp$);
var $elm$core$Dict$removeHelpEQGT$ = function (targetKey, dict) {
	if (dict.$ === 'RBNode_elm_builtin') {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var right = dict.e;
		if (_Utils_eq(targetKey, key)) {
			var _v1 = $elm$core$Dict$getMin(right);
			if (_v1.$ === 'RBNode_elm_builtin') {
				var minKey = _v1.b;
				var minValue = _v1.c;
				return $elm$core$Dict$balance$(
					color,
					minKey,
					minValue,
					left,
					$elm$core$Dict$removeMin(right));
			} else {
				return $elm$core$Dict$RBEmpty_elm_builtin;
			}
		} else {
			return $elm$core$Dict$balance$(
				color,
				key,
				value,
				left,
				$elm$core$Dict$removeHelp$(targetKey, right));
		}
	} else {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	}
};
var $elm$core$Dict$removeHelpEQGT = F2($elm$core$Dict$removeHelpEQGT$);
var $elm$core$Dict$remove$ = function (key, dict) {
	var _v0 = $elm$core$Dict$removeHelp$(key, dict);
	if ((_v0.$ === 'RBNode_elm_builtin') && (_v0.a.$ === 'Red')) {
		var _v1 = _v0.a;
		var k = _v0.b;
		var v = _v0.c;
		var l = _v0.d;
		var r = _v0.e;
		return $elm$core$Dict$RBNode_elm_builtin$($elm$core$Dict$Black, k, v, l, r);
	} else {
		var x = _v0;
		return x;
	}
};
var $elm$core$Dict$remove = F2($elm$core$Dict$remove$);
var $elm$core$Dict$update$ = function (targetKey, alter, dictionary) {
	var _v0 = alter(
		$elm$core$Dict$get$(targetKey, dictionary));
	if (_v0.$ === 'Just') {
		var value = _v0.a;
		return $elm$core$Dict$insert$(targetKey, value, dictionary);
	} else {
		return $elm$core$Dict$remove$(targetKey, dictionary);
	}
};
var $elm$core$Dict$update = F3($elm$core$Dict$update$);
var $elm$core$Basics$composeR$ = function (f, g, x) {
	return g(
		f(x));
};
var $elm$core$Basics$composeR = F3($elm$core$Basics$composeR$);
var $elm$http$Http$expectStringResponse$ = function (toMsg, toResult) {
	return A3(
		_Http_expect,
		'',
		$elm$core$Basics$identity,
		A2($elm$core$Basics$composeR, toResult, toMsg));
};
var $elm$http$Http$expectStringResponse = F2($elm$http$Http$expectStringResponse$);
var $elm$core$Result$mapError$ = function (f, result) {
	if (result.$ === 'Ok') {
		var v = result.a;
		return $elm$core$Result$Ok(v);
	} else {
		var e = result.a;
		return $elm$core$Result$Err(
			f(e));
	}
};
var $elm$core$Result$mapError = F2($elm$core$Result$mapError$);
var $elm$http$Http$BadBody = function (a) {
	return {$: 'BadBody', a: a};
};
var $elm$http$Http$BadStatus = function (a) {
	return {$: 'BadStatus', a: a};
};
var $elm$http$Http$BadUrl = function (a) {
	return {$: 'BadUrl', a: a};
};
var $elm$http$Http$NetworkError = {$: 'NetworkError'};
var $elm$http$Http$Timeout = {$: 'Timeout'};
var $elm$http$Http$resolve$ = function (toResult, response) {
	switch (response.$) {
		case 'BadUrl_':
			var url = response.a;
			return $elm$core$Result$Err(
				$elm$http$Http$BadUrl(url));
		case 'Timeout_':
			return $elm$core$Result$Err($elm$http$Http$Timeout);
		case 'NetworkError_':
			return $elm$core$Result$Err($elm$http$Http$NetworkError);
		case 'BadStatus_':
			var metadata = response.a;
			return $elm$core$Result$Err(
				$elm$http$Http$BadStatus(metadata.statusCode));
		default:
			var body = response.b;
			return $elm$core$Result$mapError$(
				$elm$http$Http$BadBody,
				toResult(body));
	}
};
var $elm$http$Http$resolve = F2($elm$http$Http$resolve$);
var $elm$http$Http$expectJson$ = function (toMsg, decoder) {
	return $elm$http$Http$expectStringResponse$(
		toMsg,
		$elm$http$Http$resolve(
			function (string) {
				return $elm$core$Result$mapError$(
					$elm$json$Json$Decode$errorToString,
					A2($elm$json$Json$Decode$decodeString, decoder, string));
			}));
};
var $elm$http$Http$expectJson = F2($elm$http$Http$expectJson$);
var $elm$http$Http$emptyBody = _Http_emptyBody;
var $elm$http$Http$Request = function (a) {
	return {$: 'Request', a: a};
};
var $elm$http$Http$State$ = function (reqs, subs) {
	return {reqs: reqs, subs: subs};
};
var $elm$http$Http$State = F2($elm$http$Http$State$);
var $elm$http$Http$init = $elm$core$Task$succeed(
	$elm$http$Http$State$($elm$core$Dict$empty, _List_Nil));
var $elm$http$Http$updateReqs$ = function (router, cmds, reqs) {
	updateReqs:
	while (true) {
		if (!cmds.b) {
			return $elm$core$Task$succeed(reqs);
		} else {
			var cmd = cmds.a;
			var otherCmds = cmds.b;
			if (cmd.$ === 'Cancel') {
				var tracker = cmd.a;
				var _v2 = $elm$core$Dict$get$(tracker, reqs);
				if (_v2.$ === 'Nothing') {
					var $temp$cmds = otherCmds;
					cmds = $temp$cmds;
					continue updateReqs;
				} else {
					var pid = _v2.a;
					return A2(
						$elm$core$Task$andThen,
						function (_v3) {
							return $elm$http$Http$updateReqs$(
								router,
								otherCmds,
								$elm$core$Dict$remove$(tracker, reqs));
						},
						$elm$core$Process$kill(pid));
				}
			} else {
				var req = cmd.a;
				return A2(
					$elm$core$Task$andThen,
					function (pid) {
						var _v4 = req.tracker;
						if (_v4.$ === 'Nothing') {
							return $elm$http$Http$updateReqs$(router, otherCmds, reqs);
						} else {
							var tracker = _v4.a;
							return $elm$http$Http$updateReqs$(
								router,
								otherCmds,
								$elm$core$Dict$insert$(tracker, pid, reqs));
						}
					},
					$elm$core$Process$spawn(
						A3(
							_Http_toTask,
							router,
							$elm$core$Platform$sendToApp(router),
							req)));
			}
		}
	}
};
var $elm$http$Http$updateReqs = F3($elm$http$Http$updateReqs$);
var $elm$http$Http$onEffects$ = function (router, cmds, subs, state) {
	return A2(
		$elm$core$Task$andThen,
		function (reqs) {
			return $elm$core$Task$succeed(
				$elm$http$Http$State$(reqs, subs));
		},
		$elm$http$Http$updateReqs$(router, cmds, state.reqs));
};
var $elm$http$Http$onEffects = F4($elm$http$Http$onEffects$);
var $elm$core$List$maybeCons$ = function (f, mx, xs) {
	var _v0 = f(mx);
	if (_v0.$ === 'Just') {
		var x = _v0.a;
		return A2($elm$core$List$cons, x, xs);
	} else {
		return xs;
	}
};
var $elm$core$List$maybeCons = F3($elm$core$List$maybeCons$);
var $elm$core$List$filterMap$ = function (f, xs) {
	return $elm$core$List$foldr$(
		$elm$core$List$maybeCons(f),
		_List_Nil,
		xs);
};
var $elm$core$List$filterMap = F2($elm$core$List$filterMap$);
var $elm$http$Http$maybeSend$ = function (router, desiredTracker, progress, _v0) {
	var actualTracker = _v0.a;
	var toMsg = _v0.b;
	return _Utils_eq(desiredTracker, actualTracker) ? $elm$core$Maybe$Just(
		A2(
			$elm$core$Platform$sendToApp,
			router,
			toMsg(progress))) : $elm$core$Maybe$Nothing;
};
var $elm$http$Http$maybeSend = F4($elm$http$Http$maybeSend$);
var $elm$http$Http$onSelfMsg$ = function (router, _v0, state) {
	var tracker = _v0.a;
	var progress = _v0.b;
	return A2(
		$elm$core$Task$andThen,
		function (_v1) {
			return $elm$core$Task$succeed(state);
		},
		$elm$core$Task$sequence(
			$elm$core$List$filterMap$(
				A3($elm$http$Http$maybeSend, router, tracker, progress),
				state.subs)));
};
var $elm$http$Http$onSelfMsg = F3($elm$http$Http$onSelfMsg$);
var $elm$http$Http$Cancel = function (a) {
	return {$: 'Cancel', a: a};
};
var $elm$http$Http$cmdMap$ = function (func, cmd) {
	if (cmd.$ === 'Cancel') {
		var tracker = cmd.a;
		return $elm$http$Http$Cancel(tracker);
	} else {
		var r = cmd.a;
		return $elm$http$Http$Request(
			{
				allowCookiesFromOtherDomains: r.allowCookiesFromOtherDomains,
				body: r.body,
				expect: A2(_Http_mapExpect, func, r.expect),
				headers: r.headers,
				method: r.method,
				timeout: r.timeout,
				tracker: r.tracker,
				url: r.url
			});
	}
};
var $elm$http$Http$cmdMap = F2($elm$http$Http$cmdMap$);
var $elm$http$Http$MySub$ = function (a, b) {
	return {$: 'MySub', a: a, b: b};
};
var $elm$http$Http$MySub = F2($elm$http$Http$MySub$);
var $elm$http$Http$subMap$ = function (func, _v0) {
	var tracker = _v0.a;
	var toMsg = _v0.b;
	return $elm$http$Http$MySub$(
		tracker,
		A2($elm$core$Basics$composeR, toMsg, func));
};
var $elm$http$Http$subMap = F2($elm$http$Http$subMap$);
_Platform_effectManagers['Http'] = _Platform_createManager($elm$http$Http$init, $elm$http$Http$onEffects, $elm$http$Http$onSelfMsg, $elm$http$Http$cmdMap, $elm$http$Http$subMap);
var $elm$http$Http$command = _Platform_leaf('Http');
var $elm$http$Http$subscription = _Platform_leaf('Http');
var $elm$http$Http$request = function (r) {
	return $elm$http$Http$command(
		$elm$http$Http$Request(
			{allowCookiesFromOtherDomains: false, body: r.body, expect: r.expect, headers: r.headers, method: r.method, timeout: r.timeout, tracker: r.tracker, url: r.url}));
};
var $elm$http$Http$get = function (r) {
	return $elm$http$Http$request(
		{body: $elm$http$Http$emptyBody, expect: r.expect, headers: _List_Nil, method: 'GET', timeout: $elm$core$Maybe$Nothing, tracker: $elm$core$Maybe$Nothing, url: r.url});
};
var $author$project$Neat$Dashboard$Status$ = function (generation, bestFitness, meanFitness, wins, own, enemy, evalS, lives, sigma, pop, episodeTicks, notes, history, hall, error, paused, gpu, uptimeS, fitnessVersion, nTrain, nHold, pool, champion, experiment, phase, evaluator, generationS, scoringVersion) {
	return {bestFitness: bestFitness, champion: champion, enemy: enemy, episodeTicks: episodeTicks, error: error, evalS: evalS, evaluator: evaluator, experiment: experiment, fitnessVersion: fitnessVersion, generation: generation, generationS: generationS, gpu: gpu, hall: hall, history: history, lives: lives, meanFitness: meanFitness, nHold: nHold, nTrain: nTrain, notes: notes, own: own, paused: paused, phase: phase, pool: pool, pop: pop, scoringVersion: scoringVersion, sigma: sigma, uptimeS: uptimeS, wins: wins};
};
var $author$project$Neat$Dashboard$Status = function (generation) {
	return function (bestFitness) {
		return function (meanFitness) {
			return function (wins) {
				return function (own) {
					return function (enemy) {
						return function (evalS) {
							return function (lives) {
								return function (sigma) {
									return function (pop) {
										return function (episodeTicks) {
											return function (notes) {
												return function (history) {
													return function (hall) {
														return function (error) {
															return function (paused) {
																return function (gpu) {
																	return function (uptimeS) {
																		return function (fitnessVersion) {
																			return function (nTrain) {
																				return function (nHold) {
																					return function (pool) {
																						return function (champion) {
																							return function (experiment) {
																								return function (phase) {
																									return function (evaluator) {
																										return function (generationS) {
																											return function (scoringVersion) {
																												return $author$project$Neat$Dashboard$Status$(generation, bestFitness, meanFitness, wins, own, enemy, evalS, lives, sigma, pop, episodeTicks, notes, history, hall, error, paused, gpu, uptimeS, fitnessVersion, nTrain, nHold, pool, champion, experiment, phase, evaluator, generationS, scoringVersion);
																											};
																										};
																									};
																								};
																							};
																						};
																					};
																				};
																			};
																		};
																	};
																};
															};
														};
													};
												};
											};
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $author$project$Neat$Dashboard$Champion$ = function (generation, fitness, coreDual, seatWins, fights) {
	return {coreDual: coreDual, fights: fights, fitness: fitness, generation: generation, seatWins: seatWins};
};
var $author$project$Neat$Dashboard$Champion = F5($author$project$Neat$Dashboard$Champion$);
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
var $author$project$Neat$Dashboard$boolish = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			$elm$json$Json$Decode$bool,
			$elm$json$Json$Decode$null(false)
		]));
var $author$project$Neat$Dashboard$Fight$ = function (seed, swap, us, them, foe, group, winner, outcome, own, enemy, ticks) {
	return {enemy: enemy, foe: foe, group: group, outcome: outcome, own: own, seed: seed, swap: swap, them: them, ticks: ticks, us: us, winner: winner};
};
var $author$project$Neat$Dashboard$Fight = function (seed) {
	return function (swap) {
		return function (us) {
			return function (them) {
				return function (foe) {
					return function (group) {
						return function (winner) {
							return function (outcome) {
								return function (own) {
									return function (enemy) {
										return function (ticks) {
											return $author$project$Neat$Dashboard$Fight$(seed, swap, us, them, foe, group, winner, outcome, own, enemy, ticks);
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$core$Basics$round = _Basics_round;
var $author$project$Neat$Dashboard$intish = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			$elm$json$Json$Decode$int,
			A2($elm$json$Json$Decode$map, $elm$core$Basics$round, $elm$json$Json$Decode$float),
			$elm$json$Json$Decode$succeed(0)
		]));
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom = $elm$json$Json$Decode$map2($elm$core$Basics$apR);
var $elm$json$Json$Decode$andThen = _Json_andThen;
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$json$Json$Decode$at$ = function (fields, decoder) {
	return $elm$core$List$foldr$($elm$json$Json$Decode$field, decoder, fields);
};
var $elm$json$Json$Decode$at = F2($elm$json$Json$Decode$at$);
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $elm$json$Json$Decode$value = _Json_decodeValue;
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder$ = function (path, valDecoder, fallback) {
	var nullOr = function (decoder) {
		return $elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					decoder,
					$elm$json$Json$Decode$null(fallback)
				]));
	};
	var handleResult = function (input) {
		var _v0 = A2(
			$elm$json$Json$Decode$decodeValue,
			$elm$json$Json$Decode$at$(path, $elm$json$Json$Decode$value),
			input);
		if (_v0.$ === 'Ok') {
			var rawValue = _v0.a;
			var _v1 = A2(
				$elm$json$Json$Decode$decodeValue,
				nullOr(valDecoder),
				rawValue);
			if (_v1.$ === 'Ok') {
				var finalResult = _v1.a;
				return $elm$json$Json$Decode$succeed(finalResult);
			} else {
				return $elm$json$Json$Decode$at$(
					path,
					nullOr(valDecoder));
			}
		} else {
			return $elm$json$Json$Decode$succeed(fallback);
		}
	};
	return A2($elm$json$Json$Decode$andThen, handleResult, $elm$json$Json$Decode$value);
};
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder = F3($NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder$);
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$ = function (key, valDecoder, fallback, decoder) {
	return A2(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optionalDecoder$(
			_List_fromArray(
				[key]),
			valDecoder,
			fallback),
		decoder);
};
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional = F4($NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$);
var $elm$json$Json$Decode$string = _Json_decodeString;
var $author$project$Neat$Dashboard$fightDecoder = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'ticks',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'enemy',
		$author$project$Neat$Dashboard$intish,
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'own',
			$author$project$Neat$Dashboard$intish,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'outcome',
				$elm$json$Json$Decode$string,
				'',
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'winner',
					$elm$json$Json$Decode$string,
					'',
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'group',
						$elm$json$Json$Decode$string,
						'',
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'foe',
							$elm$json$Json$Decode$string,
							'cyborg',
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'them',
								$elm$json$Json$Decode$string,
								'',
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'us',
									$elm$json$Json$Decode$string,
									'',
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'swap',
										$elm$json$Json$Decode$bool,
										false,
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'seed',
											$elm$json$Json$Decode$int,
											0,
											$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$Fight))))))))))));
var $author$project$Neat$Dashboard$floatish = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			$elm$json$Json$Decode$float,
			A2($elm$json$Json$Decode$map, $elm$core$Basics$toFloat, $elm$json$Json$Decode$int)
		]));
var $elm$json$Json$Decode$list = _Json_decodeList;
var $author$project$Neat$Dashboard$championDecoder = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'scenarios',
	$elm$json$Json$Decode$list($author$project$Neat$Dashboard$fightDecoder),
	_List_Nil,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'seat_wins',
		$elm$json$Json$Decode$int,
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'core_dual',
			$author$project$Neat$Dashboard$boolish,
			false,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'fitness',
				$author$project$Neat$Dashboard$floatish,
				0,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'generation',
					$elm$json$Json$Decode$int,
					0,
					$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$Champion))))));
var $author$project$Neat$Dashboard$emptyChampion = {coreDual: false, fights: _List_Nil, fitness: 0, generation: 0, seatWins: 0};
var $author$project$Neat$Dashboard$Hall$ = function (gen, fitness, winner, own, enemy, file) {
	return {enemy: enemy, file: file, fitness: fitness, gen: gen, own: own, winner: winner};
};
var $author$project$Neat$Dashboard$Hall = F6($author$project$Neat$Dashboard$Hall$);
var $elm$json$Json$Decode$map6 = _Json_map6;
var $author$project$Neat$Dashboard$hallDecoder = A7(
	$elm$json$Json$Decode$map6,
	$author$project$Neat$Dashboard$Hall,
	A2($elm$json$Json$Decode$field, 'gen', $elm$json$Json$Decode$int),
	A2($elm$json$Json$Decode$field, 'fitness', $author$project$Neat$Dashboard$floatish),
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$field, 'winner', $elm$json$Json$Decode$string),
				$elm$json$Json$Decode$succeed('')
			])),
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$field, 'own', $author$project$Neat$Dashboard$intish),
				$elm$json$Json$Decode$succeed(0)
			])),
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$field, 'enemy', $author$project$Neat$Dashboard$intish),
				$elm$json$Json$Decode$succeed(0)
			])),
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$field, 'file', $elm$json$Json$Decode$string),
				$elm$json$Json$Decode$succeed('')
			])));
var $author$project$Neat$Dashboard$Point$ = function (gen, mean, best, own, enemy, wins) {
	return {best: best, enemy: enemy, gen: gen, mean: mean, own: own, wins: wins};
};
var $author$project$Neat$Dashboard$Point = F6($author$project$Neat$Dashboard$Point$);
var $author$project$Neat$Dashboard$pointDecoder = A7(
	$elm$json$Json$Decode$map6,
	$author$project$Neat$Dashboard$Point,
	A2($elm$json$Json$Decode$field, 'gen', $elm$json$Json$Decode$int),
	A2($elm$json$Json$Decode$field, 'mean', $author$project$Neat$Dashboard$floatish),
	A2($elm$json$Json$Decode$field, 'best', $author$project$Neat$Dashboard$floatish),
	A2($elm$json$Json$Decode$field, 'own', $author$project$Neat$Dashboard$floatish),
	A2($elm$json$Json$Decode$field, 'enemy', $author$project$Neat$Dashboard$floatish),
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$field, 'wins', $elm$json$Json$Decode$int),
				$elm$json$Json$Decode$succeed(0)
			])));
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$ = function (key, valDecoder, decoder) {
	return A2(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
		A2($elm$json$Json$Decode$field, key, valDecoder),
		decoder);
};
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required = F3($NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$);
var $author$project$Neat$Dashboard$statusDecoder = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'scoring_version',
	$elm$json$Json$Decode$string,
	'unknown',
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'generation_s',
		$author$project$Neat$Dashboard$floatish,
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'evaluator',
			$elm$json$Json$Decode$string,
			'elm',
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'phase',
				$elm$json$Json$Decode$string,
				'',
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'experiment',
					$elm$json$Json$Decode$string,
					'',
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'champion',
						$author$project$Neat$Dashboard$championDecoder,
						$author$project$Neat$Dashboard$emptyChampion,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'pool',
							$elm$json$Json$Decode$list($elm$json$Json$Decode$string),
							_List_Nil,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'n_hold',
								$elm$json$Json$Decode$int,
								0,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'n_train',
									$elm$json$Json$Decode$int,
									0,
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'fitness_version',
										$elm$json$Json$Decode$string,
										'',
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'uptime_s',
											$author$project$Neat$Dashboard$floatish,
											0,
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
												'gpu',
												$elm$json$Json$Decode$bool,
												false,
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
													'paused',
													$elm$json$Json$Decode$bool,
													false,
													$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
														'error',
														$elm$json$Json$Decode$string,
														'',
														$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
															'hall',
															$elm$json$Json$Decode$list($author$project$Neat$Dashboard$hallDecoder),
															_List_Nil,
															$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																'history',
																$elm$json$Json$Decode$list($author$project$Neat$Dashboard$pointDecoder),
																_List_Nil,
																$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																	'notes',
																	$elm$json$Json$Decode$string,
																	'',
																	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																		'episode_ticks',
																		$elm$json$Json$Decode$int,
																		0,
																		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																			'pop',
																			$elm$json$Json$Decode$int,
																			0,
																			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																				'sigma',
																				$author$project$Neat$Dashboard$floatish,
																				0,
																				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																					'lives',
																					$elm$json$Json$Decode$int,
																					0,
																					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																						'eval_s',
																						$author$project$Neat$Dashboard$floatish,
																						0,
																						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
																							'enemy',
																							$author$project$Neat$Dashboard$floatish,
																							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
																								'own',
																								$author$project$Neat$Dashboard$floatish,
																								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																									'wins',
																									$elm$json$Json$Decode$int,
																									0,
																									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
																										'mean_fitness',
																										$author$project$Neat$Dashboard$floatish,
																										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
																											'best_fitness',
																											$author$project$Neat$Dashboard$floatish,
																											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
																												'generation',
																												$elm$json$Json$Decode$int,
																												$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$Status)))))))))))))))))))))))))))));
var $author$project$Neat$Dashboard$fetch = $elm$http$Http$get(
	{
		expect: $elm$http$Http$expectJson$($author$project$Neat$Dashboard$Got, $author$project$Neat$Dashboard$statusDecoder),
		url: '/api/status'
	});
var $author$project$Neat$Dashboard$GotNet = function (a) {
	return {$: 'GotNet', a: a};
};
var $elm$json$Json$Decode$fail = _Json_fail;
var $elm$core$Array$fromListHelp$ = function (list, nodeList, nodeListSize) {
	fromListHelp:
	while (true) {
		var _v0 = A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, list);
		var jsArray = _v0.a;
		var remainingItems = _v0.b;
		if (_Utils_cmp(
			$elm$core$Elm$JsArray$length(jsArray),
			$elm$core$Array$branchFactor) < 0) {
			return $elm$core$Array$builderToArray$(
				true,
				{nodeList: nodeList, nodeListSize: nodeListSize, tail: jsArray});
		} else {
			var $temp$list = remainingItems,
				$temp$nodeList = A2(
				$elm$core$List$cons,
				$elm$core$Array$Leaf(jsArray),
				nodeList),
				$temp$nodeListSize = nodeListSize + 1;
			list = $temp$list;
			nodeList = $temp$nodeList;
			nodeListSize = $temp$nodeListSize;
			continue fromListHelp;
		}
	}
};
var $elm$core$Array$fromListHelp = F3($elm$core$Array$fromListHelp$);
var $elm$core$Array$fromList = function (list) {
	if (!list.b) {
		return $elm$core$Array$empty;
	} else {
		return $elm$core$Array$fromListHelp$(list, _List_Nil, 0);
	}
};
var $author$project$Neat$Dashboard$acceptNet = function (r) {
	return (_Utils_eq(
		$elm$core$List$length(r.weights),
		(r.nHidden * r.nIn) + (r.nOut * (r.nHidden + 1))) && ((r.nIn > 0) && ((r.nHidden > 0) && (r.nOut > 0)))) ? $elm$json$Json$Decode$succeed(
		{
			generation: r.generation,
			nHidden: r.nHidden,
			nIn: r.nIn,
			nOut: r.nOut,
			weights: $elm$core$Array$fromList(r.weights)
		}) : $elm$json$Json$Decode$fail('net width');
};
var $author$project$Neat$Dashboard$rawNet$ = function (g, ni, nh, no, w) {
	return {generation: g, nHidden: nh, nIn: ni, nOut: no, weights: w};
};
var $author$project$Neat$Dashboard$rawNet = F5($author$project$Neat$Dashboard$rawNet$);
var $author$project$Neat$Dashboard$netDecoder = A2(
	$elm$json$Json$Decode$andThen,
	$author$project$Neat$Dashboard$acceptNet,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'weights',
		$elm$json$Json$Decode$list($author$project$Neat$Dashboard$floatish),
		_List_Nil,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'n_out',
			$elm$json$Json$Decode$int,
			13,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'n_hidden',
				$elm$json$Json$Decode$int,
				16,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'n_in',
					$elm$json$Json$Decode$int,
					57,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'generation',
						$elm$json$Json$Decode$int,
						0,
						$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$rawNet)))))));
var $author$project$Neat$Dashboard$fetchNet = $elm$http$Http$get(
	{
		expect: $elm$http$Http$expectJson$($author$project$Neat$Dashboard$GotNet, $author$project$Neat$Dashboard$netDecoder),
		url: '/api/net'
	});
var $author$project$Neat$Dashboard$GotReview = function (a) {
	return {$: 'GotReview', a: a};
};
var $author$project$Neat$Dashboard$Review$ = function (phase, lane, hypothesis, error, age, active, next, now, history, trialGeneration, targetGenerations, screen, freshCheck) {
	return {active: active, age: age, error: error, freshCheck: freshCheck, history: history, hypothesis: hypothesis, lane: lane, next: next, now: now, phase: phase, screen: screen, targetGenerations: targetGenerations, trialGeneration: trialGeneration};
};
var $author$project$Neat$Dashboard$Review = function (phase) {
	return function (lane) {
		return function (hypothesis) {
			return function (error) {
				return function (age) {
					return function (active) {
						return function (next) {
							return function (now) {
								return function (history) {
									return function (trialGeneration) {
										return function (targetGenerations) {
											return function (screen) {
												return function (freshCheck) {
													return $author$project$Neat$Dashboard$Review$(phase, lane, hypothesis, error, age, active, next, now, history, trialGeneration, targetGenerations, screen, freshCheck);
												};
											};
										};
									};
								};
							};
						};
					};
				};
			};
		};
	};
};
var $elm$json$Json$Decode$map3 = _Json_map3;
var $author$project$Neat$Dashboard$ReviewResult$ = function (cycle, lane, decision, baseline, challenger, fights, hypothesis, _arguments) {
	return {_arguments: _arguments, baseline: baseline, challenger: challenger, cycle: cycle, decision: decision, fights: fights, hypothesis: hypothesis, lane: lane};
};
var $author$project$Neat$Dashboard$ReviewResult = F8($author$project$Neat$Dashboard$ReviewResult$);
var $elm$core$Basics$negate = function (n) {
	return -n;
};
var $author$project$Neat$Dashboard$reviewResultDecoder = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'arguments',
	A3(
		$elm$json$Json$Decode$map2,
		F2(
			function (a, b) {
				return _List_fromArray(
					['Case for: ' + a, 'Case against: ' + b]);
			}),
		A2($elm$json$Json$Decode$field, 'case_for', $elm$json$Json$Decode$string),
		A2($elm$json$Json$Decode$field, 'case_against', $elm$json$Json$Decode$string)),
	_List_Nil,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'hypothesis',
		$elm$json$Json$Decode$string,
		'Interrupted before completion',
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'audit_fights',
			$elm$json$Json$Decode$int,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'challenger_wins',
				$elm$json$Json$Decode$int,
				-1,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'baseline_wins',
					$elm$json$Json$Decode$int,
					-1,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
						'decision',
						$elm$json$Json$Decode$string,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
							'lane',
							$elm$json$Json$Decode$string,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
								'cycle',
								$elm$json$Json$Decode$int,
								$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$ReviewResult)))))))));
var $author$project$Neat$Dashboard$reviewDecoder = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'health_check',
	$elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$at$(
				_List_fromArray(
					['fresh_check']),
				A4(
					$elm$json$Json$Decode$map3,
					F3(
						function (before, after, count) {
							return 'Last fresh-seed check: ' + ($elm$core$String$fromInt(before) + (' → ' + ($elm$core$String$fromInt(after) + (' wins / ' + ($elm$core$String$fromInt(count) + ' fresh fights versus its reference policy. This is diagnostic, not a deployment decision.')))));
						}),
					A2($elm$json$Json$Decode$field, 'before_wins', $elm$json$Json$Decode$int),
					A2($elm$json$Json$Decode$field, 'after_wins', $elm$json$Json$Decode$int),
					A2($elm$json$Json$Decode$field, 'fights', $elm$json$Json$Decode$int))),
				$elm$json$Json$Decode$succeed('')
			])),
	'',
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'screen',
		$elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					A3(
					$elm$json$Json$Decode$map2,
					F2(
						function (b, c) {
							return '40-generation screening: baseline ' + ($elm$core$String$fromInt(b) + (', challenger ' + ($elm$core$String$fromInt(c) + ' wins / 90 fights. These seeds cannot qualify a deployment.')));
						}),
					A2($elm$json$Json$Decode$field, 'baseline', $elm$json$Json$Decode$int),
					A2($elm$json$Json$Decode$field, 'challenger', $elm$json$Json$Decode$int)),
					$elm$json$Json$Decode$null('')
				])),
		'',
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'target_generations',
			$elm$json$Json$Decode$int,
			160,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'trial_generation',
				$elm$json$Json$Decode$int,
				0,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'history',
					$elm$json$Json$Decode$list($author$project$Neat$Dashboard$reviewResultDecoder),
					_List_Nil,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
						'server_time',
						$elm$json$Json$Decode$float,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'next_review_at',
							$elm$json$Json$Decode$float,
							0,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
								'trainer_active',
								$elm$json$Json$Decode$bool,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
									'status_age_s',
									$elm$json$Json$Decode$float,
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'error',
										$elm$json$Json$Decode$string,
										'',
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'hypothesis',
											$elm$json$Json$Decode$string,
											'First review pending',
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
												'lane',
												$elm$json$Json$Decode$string,
												'research',
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
													'phase',
													$elm$json$Json$Decode$string,
													'waiting',
													$elm$json$Json$Decode$succeed($author$project$Neat$Dashboard$Review))))))))))))));
var $author$project$Neat$Dashboard$fetchReview = $elm$http$Http$get(
	{
		expect: $elm$http$Http$expectJson$($author$project$Neat$Dashboard$GotReview, $author$project$Neat$Dashboard$reviewDecoder),
		url: '/api/review'
	});
var $author$project$Neat$Dashboard$init = {err: $elm$core$Maybe$Nothing, explainer: $elm$core$Maybe$Nothing, hoverCrew: $elm$core$Maybe$Nothing, hoverFit: $elm$core$Maybe$Nothing, net: $elm$core$Maybe$Nothing, pinned: false, review: $elm$core$Maybe$Nothing, reviewError: '', status: $elm$core$Maybe$Nothing};
var $author$project$Neat$Dashboard$httpErr = function (e) {
	switch (e.$) {
		case 'BadUrl':
			var u = e.a;
			return 'bad url ' + u;
		case 'Timeout':
			return 'status timed out';
		case 'NetworkError':
			return 'cannot reach trainer';
		case 'BadStatus':
			var n = e.a;
			return 'status HTTP ' + $elm$core$String$fromInt(n);
		default:
			var b = e.a;
			return 'bad json: ' + b;
	}
};
var $elm$core$Maybe$map$ = function (f, maybe) {
	if (maybe.$ === 'Just') {
		var value = maybe.a;
		return $elm$core$Maybe$Just(
			f(value));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$Maybe$map = F2($elm$core$Maybe$map$);
var $elm$core$Basics$neq = _Utils_notEqual;
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch(_List_Nil);
var $author$project$Neat$Dashboard$update$ = function (msg, model) {
	switch (msg.$) {
		case 'Tick':
			return _Utils_Tuple2(
				model,
				$elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[$author$project$Neat$Dashboard$fetch, $author$project$Neat$Dashboard$fetchReview])));
		case 'Got':
			if (msg.a.$ === 'Ok') {
				var s = msg.a.a;
				var needNet = function () {
					var _v1 = model.net;
					if (_v1.$ === 'Nothing') {
						return true;
					} else {
						var n = _v1.a;
						return (!_Utils_eq(n.generation, s.champion.generation)) || (!_Utils_eq(
							$elm$core$Maybe$map$(
								function ($) {
									return $.experiment;
								},
								model.status),
							$elm$core$Maybe$Just(s.experiment)));
					}
				}();
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							err: (s.error === '') ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(s.error),
							status: $elm$core$Maybe$Just(s)
						}),
					needNet ? $author$project$Neat$Dashboard$fetchNet : $elm$core$Platform$Cmd$none);
			} else {
				var e = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							err: $elm$core$Maybe$Just(
								$author$project$Neat$Dashboard$httpErr(e))
						}),
					$elm$core$Platform$Cmd$none);
			}
		case 'GotReview':
			if (msg.a.$ === 'Ok') {
				var r = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							review: $elm$core$Maybe$Just(r),
							reviewError: ''
						}),
					$elm$core$Platform$Cmd$none);
			} else {
				var e = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							reviewError: $author$project$Neat$Dashboard$httpErr(e)
						}),
					$elm$core$Platform$Cmd$none);
			}
		case 'GotNet':
			if (msg.a.$ === 'Ok') {
				var n = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							net: $elm$core$Maybe$Just(n)
						}),
					$elm$core$Platform$Cmd$none);
			} else {
				return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			}
		case 'HoverFit':
			var i = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{hoverFit: i}),
				$elm$core$Platform$Cmd$none);
		case 'HoverCrew':
			var i = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{hoverCrew: i}),
				$elm$core$Platform$Cmd$none);
		case 'ShowExplainer':
			var e = msg.a;
			return model.pinned ? _Utils_Tuple2(model, $elm$core$Platform$Cmd$none) : _Utils_Tuple2(
				_Utils_update(
					model,
					{
						explainer: $elm$core$Maybe$Just(e)
					}),
				$elm$core$Platform$Cmd$none);
		case 'HideExplainer':
			return model.pinned ? _Utils_Tuple2(model, $elm$core$Platform$Cmd$none) : _Utils_Tuple2(
				_Utils_update(
					model,
					{explainer: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 'PinExplainer':
			var e = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						explainer: $elm$core$Maybe$Just(e),
						pinned: true
					}),
				$elm$core$Platform$Cmd$none);
		default:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{explainer: $elm$core$Maybe$Nothing, pinned: false}),
				$elm$core$Platform$Cmd$none);
	}
};
var $author$project$Neat$Dashboard$update = F2($author$project$Neat$Dashboard$update$);
var $author$project$Neat$Dashboard$bg = '#0f1419';
var $author$project$Neat$Dashboard$HoverFit = function (a) {
	return {$: 'HoverFit', a: a};
};
var $author$project$Neat$Dashboard$card = '#1a222c';
var $elm$html$Html$div = _VirtualDom_node('div');
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $author$project$Neat$Dashboard$HideExplainer = {$: 'HideExplainer'};
var $author$project$Neat$Dashboard$PinExplainer = function (a) {
	return {$: 'PinExplainer', a: a};
};
var $author$project$Neat$Dashboard$ShowExplainer = function (a) {
	return {$: 'ShowExplainer', a: a};
};
var $author$project$Neat$Dashboard$gold = '#e0c29b';
var $elm$virtual_dom$VirtualDom$Normal = function (a) {
	return {$: 'Normal', a: a};
};
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$on$ = function (event, decoder) {
	return A2(
		$elm$virtual_dom$VirtualDom$on,
		event,
		$elm$virtual_dom$VirtualDom$Normal(decoder));
};
var $elm$html$Html$Events$on = F2($elm$html$Html$Events$on$);
var $elm$html$Html$Events$onMouseEnter = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseenter',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$Events$onMouseLeave = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseleave',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$span = _VirtualDom_node('span');
var $elm$virtual_dom$VirtualDom$MayStopPropagation = function (a) {
	return {$: 'MayStopPropagation', a: a};
};
var $elm$html$Html$Events$stopPropagationOn$ = function (event, decoder) {
	return A2(
		$elm$virtual_dom$VirtualDom$on,
		event,
		$elm$virtual_dom$VirtualDom$MayStopPropagation(decoder));
};
var $elm$html$Html$Events$stopPropagationOn = F2($elm$html$Html$Events$stopPropagationOn$);
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $author$project$Neat$Dashboard$infoBtn = function (e) {
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'display', 'inline-flex'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
				A2($elm$html$Html$Attributes$style, 'width', '18px'),
				A2($elm$html$Html$Attributes$style, 'height', '18px'),
				A2($elm$html$Html$Attributes$style, 'border-radius', '50%'),
				A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$gold),
				A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$gold),
				A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
				A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
				A2($elm$html$Html$Attributes$style, 'font-style', 'italic'),
				A2($elm$html$Html$Attributes$style, 'cursor', 'help'),
				A2($elm$html$Html$Attributes$style, 'flex-shrink', '0'),
				A2($elm$html$Html$Attributes$style, 'user-select', 'none'),
				$elm$html$Html$Events$onMouseEnter(
				$author$project$Neat$Dashboard$ShowExplainer(e)),
				$elm$html$Html$Events$onMouseLeave($author$project$Neat$Dashboard$HideExplainer),
				$elm$html$Html$Events$stopPropagationOn$(
				'click',
				$elm$json$Json$Decode$succeed(
					_Utils_Tuple2(
						$author$project$Neat$Dashboard$PinExplainer(e),
						true)))
			]),
		_List_fromArray(
			[
				$elm$html$Html$text('i')
			]));
};
var $author$project$Neat$Dashboard$mute = '#9aa8b5';
var $author$project$Neat$Dashboard$legend = function (series) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'display', 'flex'),
				A2($elm$html$Html$Attributes$style, 'gap', '16px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px'),
				A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
				A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
			]),
		$elm$core$List$map$(
			function (s) {
				return A2(
					$elm$html$Html$span,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$style, 'display', 'inline-block'),
									A2($elm$html$Html$Attributes$style, 'width', '10px'),
									A2($elm$html$Html$Attributes$style, 'height', '10px'),
									A2($elm$html$Html$Attributes$style, 'border-radius', '2px'),
									A2($elm$html$Html$Attributes$style, 'background', s.color),
									A2($elm$html$Html$Attributes$style, 'margin-right', '6px')
								]),
							_List_Nil),
							$elm$html$Html$text(s.label)
						]));
			},
			series));
};
var $author$project$Neat$Dashboard$line = '#2a3542';
var $elm$html$Html$p = _VirtualDom_node('p');
var $elm$core$List$append$ = function (xs, ys) {
	if (!ys.b) {
		return xs;
	} else {
		return $elm$core$List$foldr$($elm$core$List$cons, ys, xs);
	}
};
var $elm$core$List$append = F2($elm$core$List$append$);
var $elm$core$List$concat = function (lists) {
	return $elm$core$List$foldr$($elm$core$List$append, _List_Nil, lists);
};
var $elm$core$List$concatMap$ = function (f, list) {
	return $elm$core$List$concat(
		$elm$core$List$map$(f, list));
};
var $elm$core$List$concatMap = F2($elm$core$List$concatMap$);
var $elm$svg$Svg$Attributes$fill = _VirtualDom_attribute('fill');
var $elm$core$Basics$abs = function (n) {
	return (n < 0) ? (-n) : n;
};
var $elm$core$String$fromFloat = _String_fromNumber;
var $author$project$Neat$Dashboard$fmt1 = function (x) {
	return $elm$core$String$fromFloat(
		$elm$core$Basics$round(x * 10) / 10);
};
var $elm$core$Basics$ge = _Utils_ge;
var $author$project$Neat$Dashboard$fmtScore = function (x) {
	return ($elm$core$Basics$abs(x) >= 1000) ? ($elm$core$String$fromInt(
		$elm$core$Basics$round(x / 1000)) + 'k') : $author$project$Neat$Dashboard$fmt1(x);
};
var $elm$svg$Svg$Attributes$fontFamily = _VirtualDom_attribute('font-family');
var $elm$svg$Svg$Attributes$fontSize = _VirtualDom_attribute('font-size');
var $elm$svg$Svg$trustedNode = _VirtualDom_nodeNS('http://www.w3.org/2000/svg');
var $elm$svg$Svg$g = $elm$svg$Svg$trustedNode('g');
var $elm$svg$Svg$Attributes$height = _VirtualDom_attribute('height');
var $elm$svg$Svg$circle = $elm$svg$Svg$trustedNode('circle');
var $elm$svg$Svg$Attributes$cx = _VirtualDom_attribute('cx');
var $elm$svg$Svg$Attributes$cy = _VirtualDom_attribute('cy');
var $elm$core$List$drop$ = function (n, list) {
	drop:
	while (true) {
		if (n <= 0) {
			return list;
		} else {
			if (!list.b) {
				return list;
			} else {
				var x = list.a;
				var xs = list.b;
				var $temp$n = n - 1,
					$temp$list = xs;
				n = $temp$n;
				list = $temp$list;
				continue drop;
			}
		}
	}
};
var $elm$core$List$drop = F2($elm$core$List$drop$);
var $elm$svg$Svg$Attributes$fillOpacity = _VirtualDom_attribute('fill-opacity');
var $elm$core$List$head = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(x);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Neat$Dashboard$ink = '#e8eef4';
var $elm$svg$Svg$line = $elm$svg$Svg$trustedNode('line');
var $elm$svg$Svg$Attributes$r = _VirtualDom_attribute('r');
var $elm$svg$Svg$rect = $elm$svg$Svg$trustedNode('rect');
var $elm$svg$Svg$Attributes$rx = _VirtualDom_attribute('rx');
var $elm$svg$Svg$Attributes$stroke = _VirtualDom_attribute('stroke');
var $elm$svg$Svg$Attributes$strokeOpacity = _VirtualDom_attribute('stroke-opacity');
var $elm$svg$Svg$Attributes$strokeWidth = _VirtualDom_attribute('stroke-width');
var $elm$svg$Svg$Attributes$style = _VirtualDom_attribute('style');
var $elm$core$List$takeReverse$ = function (n, list, kept) {
	takeReverse:
	while (true) {
		if (n <= 0) {
			return kept;
		} else {
			if (!list.b) {
				return kept;
			} else {
				var x = list.a;
				var xs = list.b;
				var $temp$n = n - 1,
					$temp$list = xs,
					$temp$kept = A2($elm$core$List$cons, x, kept);
				n = $temp$n;
				list = $temp$list;
				kept = $temp$kept;
				continue takeReverse;
			}
		}
	}
};
var $elm$core$List$takeReverse = F3($elm$core$List$takeReverse$);
var $elm$core$List$takeTailRec$ = function (n, list) {
	return $elm$core$List$reverse(
		$elm$core$List$takeReverse$(n, list, _List_Nil));
};
var $elm$core$List$takeTailRec = F2($elm$core$List$takeTailRec$);
var $elm$core$List$takeFast$ = function (ctr, n, list) {
	if (n <= 0) {
		return _List_Nil;
	} else {
		var _v0 = _Utils_Tuple2(n, list);
		_v0$1:
		while (true) {
			_v0$5:
			while (true) {
				if (!_v0.b.b) {
					return list;
				} else {
					if (_v0.b.b.b) {
						switch (_v0.a) {
							case 1:
								break _v0$1;
							case 2:
								var _v2 = _v0.b;
								var x = _v2.a;
								var _v3 = _v2.b;
								var y = _v3.a;
								return _List_fromArray(
									[x, y]);
							case 3:
								if (_v0.b.b.b.b) {
									var _v4 = _v0.b;
									var x = _v4.a;
									var _v5 = _v4.b;
									var y = _v5.a;
									var _v6 = _v5.b;
									var z = _v6.a;
									return _List_fromArray(
										[x, y, z]);
								} else {
									break _v0$5;
								}
							default:
								if (_v0.b.b.b.b && _v0.b.b.b.b.b) {
									var _v7 = _v0.b;
									var x = _v7.a;
									var _v8 = _v7.b;
									var y = _v8.a;
									var _v9 = _v8.b;
									var z = _v9.a;
									var _v10 = _v9.b;
									var w = _v10.a;
									var tl = _v10.b;
									return (ctr > 1000) ? A2(
										$elm$core$List$cons,
										x,
										A2(
											$elm$core$List$cons,
											y,
											A2(
												$elm$core$List$cons,
												z,
												A2(
													$elm$core$List$cons,
													w,
													$elm$core$List$takeTailRec$(n - 4, tl))))) : A2(
										$elm$core$List$cons,
										x,
										A2(
											$elm$core$List$cons,
											y,
											A2(
												$elm$core$List$cons,
												z,
												A2(
													$elm$core$List$cons,
													w,
													$elm$core$List$takeFast$(ctr + 1, n - 4, tl)))));
								} else {
									break _v0$5;
								}
						}
					} else {
						if (_v0.a === 1) {
							break _v0$1;
						} else {
							break _v0$5;
						}
					}
				}
			}
			return list;
		}
		var _v1 = _v0.b;
		var x = _v1.a;
		return _List_fromArray(
			[x]);
	}
};
var $elm$core$List$takeFast = F3($elm$core$List$takeFast$);
var $elm$core$List$take$ = function (n, list) {
	return $elm$core$List$takeFast$(0, n, list);
};
var $elm$core$List$take = F2($elm$core$List$take$);
var $elm$svg$Svg$text = $elm$virtual_dom$VirtualDom$text;
var $elm$svg$Svg$text_ = $elm$svg$Svg$trustedNode('text');
var $elm$svg$Svg$Attributes$width = _VirtualDom_attribute('width');
var $elm$core$Maybe$withDefault$ = function (_default, maybe) {
	if (maybe.$ === 'Just') {
		var value = maybe.a;
		return value;
	} else {
		return _default;
	}
};
var $elm$core$Maybe$withDefault = F2($elm$core$Maybe$withDefault$);
var $elm$svg$Svg$Attributes$x = _VirtualDom_attribute('x');
var $elm$svg$Svg$Attributes$x1 = _VirtualDom_attribute('x1');
var $elm$svg$Svg$Attributes$x2 = _VirtualDom_attribute('x2');
var $elm$svg$Svg$Attributes$y = _VirtualDom_attribute('y');
var $elm$svg$Svg$Attributes$y1 = _VirtualDom_attribute('y1');
var $elm$svg$Svg$Attributes$y2 = _VirtualDom_attribute('y2');
var $author$project$Neat$Dashboard$hoverTooltip$ = function (series, history, padL, padT, plotW, plotH, xOf, yOf, idx) {
	var _v0 = $elm$core$List$head(
		$elm$core$List$drop$(idx, history));
	if (_v0.$ === 'Nothing') {
		return _List_Nil;
	} else {
		var pt = _v0.a;
		var yMain = $elm$core$Maybe$withDefault$(
			0,
			$elm$core$List$head(
				$elm$core$List$drop$(
					idx,
					$elm$core$List$concatMap$(
						function ($) {
							return $.values;
						},
						$elm$core$List$take$(1, series)))));
		var x = xOf(idx);
		var tooltipY = padT + 8;
		var tooltipW = 240.0;
		var tooltipX = (_Utils_cmp((x + tooltipW) + 14, padL + plotW) > 0) ? ((x - tooltipW) - 14) : (x + 14);
		var rows = A2(
			$elm$core$List$cons,
			_Utils_Tuple3(
				'Generation',
				$author$project$Neat$Dashboard$ink,
				$elm$core$String$fromInt(pt.gen)),
			_Utils_ap(
				$elm$core$List$filterMap$(
					function (s) {
						return $elm$core$Maybe$map$(
							function (v) {
								return _Utils_Tuple3(
									s.label,
									s.color,
									$author$project$Neat$Dashboard$fmtScore(v));
							},
							$elm$core$List$head(
								$elm$core$List$drop$(idx, s.values)));
					},
					series),
				_List_fromArray(
					[
						_Utils_Tuple3(
						'leftover crew us / them',
						$author$project$Neat$Dashboard$mute,
						$author$project$Neat$Dashboard$fmt1(pt.own) + (' / ' + $author$project$Neat$Dashboard$fmt1(pt.enemy)))
					])));
		var lineH = 16.0;
		var tooltipH = ($elm$core$List$length(rows) * lineH) + 14;
		return _Utils_ap(
			_List_fromArray(
				[
					A2(
					$elm$svg$Svg$line,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x1(
							$elm$core$String$fromFloat(x)),
							$elm$svg$Svg$Attributes$x2(
							$elm$core$String$fromFloat(x)),
							$elm$svg$Svg$Attributes$y1(
							$elm$core$String$fromInt(padT)),
							$elm$svg$Svg$Attributes$y2(
							$elm$core$String$fromInt(padT + plotH)),
							$elm$svg$Svg$Attributes$stroke($author$project$Neat$Dashboard$gold),
							$elm$svg$Svg$Attributes$strokeWidth('1'),
							$elm$svg$Svg$Attributes$strokeOpacity('0.35'),
							$elm$svg$Svg$Attributes$style('pointer-events:none')
						]),
					_List_Nil),
					A2(
					$elm$svg$Svg$circle,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$cx(
							$elm$core$String$fromFloat(x)),
							$elm$svg$Svg$Attributes$cy(
							$elm$core$String$fromFloat(
								yOf(yMain))),
							$elm$svg$Svg$Attributes$r('4.5'),
							$elm$svg$Svg$Attributes$fill($author$project$Neat$Dashboard$gold),
							$elm$svg$Svg$Attributes$stroke('#fff'),
							$elm$svg$Svg$Attributes$strokeWidth('2'),
							$elm$svg$Svg$Attributes$style('pointer-events:none')
						]),
					_List_Nil),
					A2(
					$elm$svg$Svg$rect,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat(tooltipX)),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat(tooltipY)),
							$elm$svg$Svg$Attributes$width(
							$elm$core$String$fromFloat(tooltipW)),
							$elm$svg$Svg$Attributes$height(
							$elm$core$String$fromFloat(tooltipH)),
							$elm$svg$Svg$Attributes$rx('6'),
							$elm$svg$Svg$Attributes$fill('#1e293b'),
							$elm$svg$Svg$Attributes$fillOpacity('0.95'),
							$elm$svg$Svg$Attributes$style('pointer-events:none')
						]),
					_List_Nil)
				]),
			$elm$core$List$indexedMap$(
				F2(
					function (i, _v1) {
						var lab = _v1.a;
						var col = _v1.b;
						var val = _v1.c;
						return A2(
							$elm$svg$Svg$text_,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$x(
									$elm$core$String$fromFloat(tooltipX + 10)),
									$elm$svg$Svg$Attributes$y(
									$elm$core$String$fromFloat((tooltipY + 16) + (i * lineH))),
									$elm$svg$Svg$Attributes$fill(col),
									$elm$svg$Svg$Attributes$fontSize('11'),
									$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif'),
									$elm$svg$Svg$Attributes$style('pointer-events:none')
								]),
							_List_fromArray(
								[
									$elm$svg$Svg$text(lab + ('  ' + val))
								]));
					}),
				rows));
	}
};
var $author$project$Neat$Dashboard$hoverTooltip = F9($author$project$Neat$Dashboard$hoverTooltip$);
var $elm$core$List$maximum = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(
			$elm$core$List$foldl$($elm$core$Basics$max, x, xs));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$Basics$min$ = function (x, y) {
	return (_Utils_cmp(x, y) < 0) ? x : y;
};
var $elm$core$Basics$min = F2($elm$core$Basics$min$);
var $elm$core$List$minimum = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(
			$elm$core$List$foldl$($elm$core$Basics$min, x, xs));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$svg$Svg$Events$onMouseOut = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseout',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$svg$Svg$Events$onMouseOver = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseover',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$svg$Svg$Attributes$points = _VirtualDom_attribute('points');
var $elm$svg$Svg$polyline = $elm$svg$Svg$trustedNode('polyline');
var $elm$svg$Svg$Attributes$strokeDasharray = _VirtualDom_attribute('stroke-dasharray');
var $elm$svg$Svg$Attributes$strokeLinecap = _VirtualDom_attribute('stroke-linecap');
var $elm$svg$Svg$Attributes$strokeLinejoin = _VirtualDom_attribute('stroke-linejoin');
var $elm$svg$Svg$svg = $elm$svg$Svg$trustedNode('svg');
var $elm$svg$Svg$Attributes$textAnchor = _VirtualDom_attribute('text-anchor');
var $elm$svg$Svg$Attributes$viewBox = _VirtualDom_attribute('viewBox');
var $author$project$Neat$Dashboard$viewChart$ = function (series, history, hover, hoverMsg) {
	var padT = 16;
	var padR = 16;
	var padL = 58;
	var padB = 28;
	var n = $elm$core$List$length(history);
	var chartW = 920;
	var plotW = (chartW - padL) - padR;
	var xStep = (n <= 1) ? plotW : (plotW / (n - 1));
	var xOf = function (i) {
		return padL + (i * xStep);
	};
	var chartH = 260;
	var plotH = (chartH - padT) - padB;
	var hits = $elm$core$List$indexedMap$(
		F2(
			function (i, _v1) {
				return A2(
					$elm$svg$Svg$rect,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat(
								xOf(i) - (xStep / 2))),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromInt(padT)),
							$elm$svg$Svg$Attributes$width(
							$elm$core$String$fromFloat(
								$elm$core$Basics$max$(4, xStep))),
							$elm$svg$Svg$Attributes$height(
							$elm$core$String$fromInt(plotH)),
							$elm$svg$Svg$Attributes$fill('transparent'),
							$elm$svg$Svg$Events$onMouseOver(
							hoverMsg(
								$elm$core$Maybe$Just(i))),
							$elm$svg$Svg$Events$onMouseOut(
							hoverMsg($elm$core$Maybe$Nothing))
						]),
					_List_Nil);
			}),
		history);
	var allVals = $elm$core$List$concatMap$(
		function ($) {
			return $.values;
		},
		series);
	var hi0 = $elm$core$Maybe$withDefault$(
		1,
		$elm$core$List$maximum(allVals));
	var lo0 = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$minimum(allVals));
	var lo = $elm$core$Basics$min$(lo0, 0);
	var hi = _Utils_eq(hi0, lo) ? (lo + 1) : hi0;
	var yOf = function (v) {
		return padT + (plotH * (1 - ((v - lo) / (hi - lo))));
	};
	var grid = $elm$core$List$map$(
		function (i) {
			var val = lo + (((hi - lo) * i) / 4);
			var y = yOf(val);
			return A2(
				$elm$svg$Svg$g,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$svg$Svg$line,
						_List_fromArray(
							[
								$elm$svg$Svg$Attributes$x1(
								$elm$core$String$fromInt(padL)),
								$elm$svg$Svg$Attributes$x2(
								$elm$core$String$fromInt(padL + plotW)),
								$elm$svg$Svg$Attributes$y1(
								$elm$core$String$fromFloat(y)),
								$elm$svg$Svg$Attributes$y2(
								$elm$core$String$fromFloat(y)),
								$elm$svg$Svg$Attributes$stroke($author$project$Neat$Dashboard$line),
								$elm$svg$Svg$Attributes$strokeWidth('0.5'),
								$elm$svg$Svg$Attributes$strokeDasharray('3,3')
							]),
						_List_Nil),
						A2(
						$elm$svg$Svg$text_,
						_List_fromArray(
							[
								$elm$svg$Svg$Attributes$x(
								$elm$core$String$fromInt(padL - 8)),
								$elm$svg$Svg$Attributes$y(
								$elm$core$String$fromFloat(y + 3.5)),
								$elm$svg$Svg$Attributes$textAnchor('end'),
								$elm$svg$Svg$Attributes$fill($author$project$Neat$Dashboard$mute),
								$elm$svg$Svg$Attributes$fontSize('10'),
								$elm$svg$Svg$Attributes$fontFamily('ui-monospace, monospace')
							]),
						_List_fromArray(
							[
								$elm$svg$Svg$text(
								$author$project$Neat$Dashboard$fmtScore(val))
							]))
					]));
		},
		$elm$core$List$range$(0, 4));
	var hoverBits = function () {
		if (hover.$ === 'Nothing') {
			return _List_Nil;
		} else {
			var idx = hover.a;
			return $author$project$Neat$Dashboard$hoverTooltip$(series, history, padL, padT, plotW, plotH, xOf, yOf, idx);
		}
	}();
	var polylines = $elm$core$List$concatMap$(
		function (s) {
			var pts = $elm$core$String$join$(
				' ',
				$elm$core$List$indexedMap$(
					F2(
						function (i, v) {
							return $elm$core$String$fromFloat(
								xOf(i)) + (',' + $elm$core$String$fromFloat(
								yOf(v)));
						}),
					s.values));
			return _List_fromArray(
				[
					A2(
					$elm$svg$Svg$polyline,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$points(pts),
							$elm$svg$Svg$Attributes$fill('none'),
							$elm$svg$Svg$Attributes$stroke(s.color),
							$elm$svg$Svg$Attributes$strokeWidth('2'),
							$elm$svg$Svg$Attributes$strokeLinejoin('round'),
							$elm$svg$Svg$Attributes$strokeLinecap('round')
						]),
					_List_Nil)
				]);
		},
		series);
	return A2(
		$elm$svg$Svg$svg,
		_List_fromArray(
			[
				$elm$svg$Svg$Attributes$viewBox(
				'0 0 ' + ($elm$core$String$fromInt(chartW) + (' ' + $elm$core$String$fromInt(chartH)))),
				$elm$svg$Svg$Attributes$width('100%'),
				A2($elm$html$Html$Attributes$style, 'display', 'block')
			]),
		_Utils_ap(
			grid,
			_Utils_ap(
				polylines,
				_Utils_ap(hits, hoverBits))));
};
var $author$project$Neat$Dashboard$viewChart = F4($author$project$Neat$Dashboard$viewChart$);
var $author$project$Neat$Dashboard$chartCard$ = function (title, blurb, e, series, history, hover, hoverMsg) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$card),
				A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'border-radius', '12px'),
				A2($elm$html$Html$Attributes$style, 'padding', '16px 16px 8px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'gap', '8px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
								A2($elm$html$Html$Attributes$style, 'margin', '0'),
								A2($elm$html$Html$Attributes$style, 'font-weight', '650')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(title)
							])),
						$author$project$Neat$Dashboard$infoBtn(e)
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
						A2($elm$html$Html$Attributes$style, 'margin', '8px 0 12px'),
						A2($elm$html$Html$Attributes$style, 'line-height', '1.45')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(blurb)
					])),
				$author$project$Neat$Dashboard$legend(series),
				($elm$core$List$length(history) < 2) ? A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						'Waiting for two completed generations in this experiment. Completed: ' + ($elm$core$String$fromInt(
							$elm$core$List$length(history)) + '. The evaluation counter advances while the next generation runs.'))
					])) : $author$project$Neat$Dashboard$viewChart$(series, history, hover, hoverMsg)
			]));
};
var $author$project$Neat$Dashboard$chartCard = F7($author$project$Neat$Dashboard$chartCard$);
var $author$project$Neat$Dashboard$mint = '#5dcea8';
var $author$project$Neat$Dashboard$scoreChartExplainer = function (s) {
	return {
		body: _List_fromArray(
			[
				'Left axis is the blended fight score, abbreviated with k for thousands. It is not kills and not crew.',
				'Mint is the saved champion\'s exam score. It is a step: it only jumps when we keep a new genome. Long flat mint means no new champion.',
				'Current exam score is ' + ($author$project$Neat$Dashboard$fmtScore(s.bestFitness) + (' at generation ' + ($elm$core$String$fromInt(s.champion.generation) + ('. Current practice average is ' + ($author$project$Neat$Dashboard$fmtScore(s.meanFitness) + '.'))))),
				'A mint jump with Hold record unchanged usually means the same number of kills, but timeouts did more damage (or kills were faster). Watch Hold record for actual new kills.'
			]),
		title: 'Saved champion score'
	};
};
var $author$project$Neat$Dashboard$charts$ = function (model, s) {
	var hist = s.history;
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'display', 'grid'),
				A2($elm$html$Html$Attributes$style, 'gap', '16px')
			]),
		_List_fromArray(
			[
				$author$project$Neat$Dashboard$chartCard$(
				'Saved champion score',
				'Validation score only. A flat line means no better champion was saved. This is a fitness tiebreaker, not a win count. History belongs to this run.',
				$author$project$Neat$Dashboard$scoreChartExplainer(s),
				_List_fromArray(
					[
						{
						color: $author$project$Neat$Dashboard$mint,
						label: 'saved validation score',
						values: $elm$core$List$map$(
							function ($) {
								return $.best;
							},
							hist)
					}
					]),
				hist,
				model.hoverFit,
				$author$project$Neat$Dashboard$HoverFit)
			]));
};
var $author$project$Neat$Dashboard$charts = F2($author$project$Neat$Dashboard$charts$);
var $author$project$Neat$Dashboard$coral = '#ff6b6b';
var $elm$html$Html$details = _VirtualDom_node('details');
var $author$project$Neat$Dashboard$Unpin = {$: 'Unpin'};
var $elm$html$Html$button = _VirtualDom_node('button');
var $author$project$Neat$Dashboard$explainerPara = function (s) {
	return A2(
		$elm$html$Html$p,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$ink),
				A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
				A2($elm$html$Html$Attributes$style, 'line-height', '1.55'),
				A2($elm$html$Html$Attributes$style, 'margin', '10px 0 0')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(s)
			]));
};
var $elm$html$Html$h3 = _VirtualDom_node('h3');
var $elm$html$Html$Events$onClick = function (msg) {
	return $elm$html$Html$Events$on$(
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $author$project$Neat$Dashboard$explainerModal = function (model) {
	var _v0 = model.explainer;
	if (_v0.$ === 'Nothing') {
		return $elm$html$Html$text('');
	} else {
		var e = _v0.a;
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					model.pinned ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'position', 'fixed'),
							A2($elm$html$Html$Attributes$style, 'inset', '0'),
							A2($elm$html$Html$Attributes$style, 'background', 'rgba(0,0,0,0.45)'),
							A2($elm$html$Html$Attributes$style, 'z-index', '40'),
							$elm$html$Html$Events$onClick($author$project$Neat$Dashboard$Unpin)
						]),
					_List_Nil) : $elm$html$Html$text(''),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'position', 'fixed'),
							A2($elm$html$Html$Attributes$style, 'right', '20px'),
							A2($elm$html$Html$Attributes$style, 'bottom', '20px'),
							A2($elm$html$Html$Attributes$style, 'width', 'min(420px, calc(100vw - 32px))'),
							A2($elm$html$Html$Attributes$style, 'max-height', '70vh'),
							A2($elm$html$Html$Attributes$style, 'overflow', 'auto'),
							A2($elm$html$Html$Attributes$style, 'background', '#151c24'),
							A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$ink),
							A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$gold),
							A2($elm$html$Html$Attributes$style, 'border-radius', '12px'),
							A2($elm$html$Html$Attributes$style, 'padding', '16px 18px 18px'),
							A2($elm$html$Html$Attributes$style, 'z-index', '50'),
							A2($elm$html$Html$Attributes$style, 'box-shadow', '0 12px 40px rgba(0,0,0,0.45)')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$style, 'display', 'flex'),
									A2($elm$html$Html$Attributes$style, 'align-items', 'flex-start'),
									A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
									A2($elm$html$Html$Attributes$style, 'gap', '12px')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$h3,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'margin', '0'),
											A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
											A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$gold),
											A2($elm$html$Html$Attributes$style, 'line-height', '1.35')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(e.title)
										])),
									model.pinned ? A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'background', 'transparent'),
											A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$line),
											A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$ink),
											A2($elm$html$Html$Attributes$style, 'border-radius', '6px'),
											A2($elm$html$Html$Attributes$style, 'padding', '2px 8px'),
											A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
											A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
											$elm$html$Html$Events$onClick($author$project$Neat$Dashboard$Unpin)
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Close')
										])) : A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
											A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
											A2($elm$html$Html$Attributes$style, 'white-space', 'nowrap')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('click i to pin')
										]))
								])),
							A2(
							$elm$html$Html$div,
							_List_Nil,
							$elm$core$List$map$($author$project$Neat$Dashboard$explainerPara, e.body))
						]))
				]));
	}
};
var $elm$html$Html$h1 = _VirtualDom_node('h1');
var $elm$core$List$isEmpty = function (xs) {
	if (!xs.b) {
		return true;
	} else {
		return false;
	}
};
var $author$project$Neat$Dashboard$pageExplainer = {
	body: _List_fromArray(
		['We are training one neural net to play Super Melee against the original Awesome cyborg. The net picks a ship, the cyborg picks a ship, they fight in the real engine.', 'Hull identity is 5 bits for us and 5 bits for them. A hidden layer of 16 tanh units sits between the sensors and the buttons. The current experiment uses Pkunk, Umgah and Yehat in both seats across several starting seeds.', 'The ship pool stays fixed during this comparison so both experiments face the same challenge.', 'Ignore leftover v5 numbers and any old \'WIN 509t\' jackpot card. The number that matters is Hold record.']),
	title: 'What this page is'
};
var $elm$core$String$trim = _String_trim;
var $elm$core$Basics$modBy = _Basics_modBy;
var $author$project$Neat$Dashboard$uptime = function (s) {
	var n = $elm$core$Basics$round(s);
	return (n < 60) ? ($elm$core$String$fromInt(n) + 's') : ((n < 3600) ? ($elm$core$String$fromInt((n / 60) | 0) + ('m ' + ($elm$core$String$fromInt(
		A2($elm$core$Basics$modBy, 60, n)) + 's'))) : ($elm$core$String$fromInt((n / 3600) | 0) + ('h ' + ($elm$core$String$fromInt(
		A2($elm$core$Basics$modBy, 60, (n / 60) | 0)) + 'm'))));
};
var $author$project$Neat$Dashboard$header = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '12px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'gap', '10px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h1,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '22px'),
								A2($elm$html$Html$Attributes$style, 'font-weight', '650'),
								A2($elm$html$Html$Attributes$style, 'margin', '0')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Melee policy training')
							])),
						$author$project$Neat$Dashboard$infoBtn($author$project$Neat$Dashboard$pageExplainer)
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
						A2($elm$html$Html$Attributes$style, 'margin', '8px 0 0'),
						A2($elm$html$Html$Attributes$style, 'max-width', '72ch'),
						A2($elm$html$Html$Attributes$style, 'line-height', '1.5'),
						A2($elm$html$Html$Attributes$style, 'font-size', '14px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('One net learning to fly Super Melee ships against the original Awesome cyborg. Hover any (i) for a plain-language explainer. Click (i) to pin it.')
					])),
				function () {
				var _v0 = model.status;
				if (_v0.$ === 'Just') {
					var s = _v0.a;
					return A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
								A2($elm$html$Html$Attributes$style, 'margin', '8px 0 0'),
								A2($elm$html$Html$Attributes$style, 'font-size', '13px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$elm$core$Maybe$withDefault$(
									'training',
									$elm$core$List$head(
										$elm$core$List$reverse(
											$elm$core$String$split$('/', s.experiment)))) + ('  ·  ' + (s.phase + (' | ' + (s.evaluator + (' / ' + (s.scoringVersion + ('  ·  ' + ($author$project$Neat$Dashboard$uptime(s.uptimeS) + ('  ·  gen ' + ($elm$core$String$fromInt(s.generation) + ('  ·  ' + ((($elm$core$String$trim(s.fitnessVersion) === '') ? 'no version' : s.fitnessVersion) + ('  ·  pool ' + (($elm$core$List$isEmpty(s.pool) ? '?' : $elm$core$String$join$(', ', s.pool)) + ('  ·  ' + ($elm$core$String$fromInt(s.nTrain) + (' train / ' + ($elm$core$String$fromInt(s.nHold) + (' hold' + (s.paused ? '  ·  PAUSED' : '')))))))))))))))))))))
							]));
				} else {
					return $elm$html$Html$text('');
				}
			}()
			]));
};
var $author$project$Neat$Dashboard$hintBar = function (model) {
	return A2(
		$elm$html$Html$p,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
				A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
				A2($elm$html$Html$Attributes$style, 'margin', '12px 0 18px')
			]),
		_List_fromArray(
			[
				$elm$html$Html$text(
				model.pinned ? 'Explainer pinned. Click the dimmed area or Close to dismiss.' : 'Watch fresh-seed improvement and time since the last better champion. Generations and evaluations measure activity, not learning.')
			]));
};
var $elm$core$List$filter$ = function (isGood, list) {
	return $elm$core$List$foldr$(
		F2(
			function (x, xs) {
				return isGood(x) ? A2($elm$core$List$cons, x, xs) : xs;
			}),
		_List_Nil,
		list);
};
var $elm$core$List$filter = F2($elm$core$List$filter$);
var $elm$json$Json$Encode$string = _Json_wrap;
var $elm$html$Html$Attributes$stringProperty$ = function (key, string) {
	return A2(
		_VirtualDom_property,
		key,
		$elm$json$Json$Encode$string(string));
};
var $elm$html$Html$Attributes$stringProperty = F2($elm$html$Html$Attributes$stringProperty$);
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $author$project$Neat$Dashboard$fightWon = function (f) {
	var seat = f.swap ? 'top' : 'bottom';
	return (f.outcome === 'completed') && (_Utils_eq(f.winner, seat) && (!f.enemy));
};
var $author$project$Neat$Dashboard$secs = function (ticks) {
	var n = ticks / 60;
	return $author$project$Neat$Dashboard$fmt1(n) + 's';
};
var $author$project$Neat$Dashboard$fightExplainer = function (f) {
	var won = $author$project$Neat$Dashboard$fightWon(f);
	var seat = f.swap ? 'top' : 'bottom';
	var result = won ? 'This is a KILL: the fight finished, our seat won, enemy crew hit 0.' : ((f.outcome === 'invalidated') ? 'This is a TIMEOUT: we hit the 30 second cap. The engine did not crash. Nobody finished the other. It counts as not a win.' : ((f.outcome === 'completed') ? ('This is a LOSS: the fight finished in the original game sense, and we were not the winner (winner reported as ' + (f.winner + ').')) : ('Outcome ' + (f.outcome + (', winner ' + (f.winner + '. Not a kill.'))))));
	return {
		body: _List_fromArray(
			[
				'We flew ' + (f.us + (' on the ' + (seat + (' seat. The opponent was frozen original Awesome cyborg flying ' + (f.them + ('. Seed ' + ($elm$core$String$fromInt(f.seed) + '.'))))))),
				result,
				'Crew left: us ' + ($elm$core$String$fromInt(f.own) + (', them ' + ($elm$core$String$fromInt(f.enemy) + ('. Duration ' + ($author$project$Neat$Dashboard$secs(f.ticks) + (' (' + ($elm$core$String$fromInt(f.ticks) + ' ticks at 60 per second).')))))))
			]),
		title: f.us + (' vs ' + (f.them + ('  (' + (seat + ' seat)'))))
	};
};
var $author$project$Neat$Dashboard$fightRow = function (f) {
	var won = $author$project$Neat$Dashboard$fightWon(f);
	var seat = f.swap ? 'top' : 'bottom';
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('fight-row'),
				A2($elm$html$Html$Attributes$style, 'display', 'grid'),
				A2($elm$html$Html$Attributes$style, 'grid-template-columns', '1.4fr 0.7fr 0.8fr 0.9fr 1.1fr'),
				A2($elm$html$Html$Attributes$style, 'gap', '8px'),
				A2($elm$html$Html$Attributes$style, 'padding', '8px 0'),
				A2($elm$html$Html$Attributes$style, 'border-top', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
				A2($elm$html$Html$Attributes$style, 'font-variant-numeric', 'tabular-nums'),
				A2($elm$html$Html$Attributes$style, 'cursor', 'help'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				$elm$html$Html$Events$onMouseEnter(
				$author$project$Neat$Dashboard$ShowExplainer(
					$author$project$Neat$Dashboard$fightExplainer(f))),
				$elm$html$Html$Events$onMouseLeave($author$project$Neat$Dashboard$HideExplainer),
				$elm$html$Html$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(
					$author$project$Neat$Dashboard$fightExplainer(f)))
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(f.us + (' vs ' + f.them))
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(seat)
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$Attributes$style,
						'color',
						won ? $author$project$Neat$Dashboard$mint : $author$project$Neat$Dashboard$coral),
						A2($elm$html$Html$Attributes$style, 'font-weight', '650')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						won ? 'KILL' : ((f.outcome === 'invalidated') ? 'TIMEOUT' : 'LOSS'))
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						'us ' + ($elm$core$String$fromInt(f.own) + ('  them ' + $elm$core$String$fromInt(f.enemy))))
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						$author$project$Neat$Dashboard$secs(f.ticks) + ('  ·  ' + ($elm$core$String$fromInt(f.ticks) + ' ticks')))
					]))
			]));
};
var $author$project$Neat$Dashboard$groupBlock$ = function (title, fights) {
	return $elm$core$List$isEmpty(fights) ? _List_Nil : _List_fromArray(
		[
			A2(
			$elm$html$Html$p,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$gold),
					A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
					A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.04em'),
					A2($elm$html$Html$Attributes$style, 'text-transform', 'uppercase'),
					A2($elm$html$Html$Attributes$style, 'margin', '12px 0 6px')
				]),
			_List_fromArray(
				[
					$elm$html$Html$text(title + '  ·  Awesome cyborg')
				])),
			A2(
			$elm$html$Html$div,
			_List_Nil,
			$elm$core$List$map$($author$project$Neat$Dashboard$fightRow, fights))
		]);
};
var $author$project$Neat$Dashboard$groupBlock = F2($author$project$Neat$Dashboard$groupBlock$);
var $author$project$Neat$Dashboard$holdTableExplainer = function (s) {
	return {
		body: _List_fromArray(
			[
				'Every row is one exam fight for the saved champion from generation ' + ($elm$core$String$fromInt(s.champion.generation) + '.'),
				'Our ship vs theirs: which hull we flew, which hull the frozen Awesome cyborg flew.',
				'Our seat: Super Melee has a bottom player and a top player. We test both, because a net that only wins from one side is not done.',
				'KILL means the fight finished, we won, enemy crew 0. TIMEOUT means we hit the 30 second cap with someone still alive. LOSS means the fight finished and we died.',
				'Crew left is ours then theirs. Duration counts combat time at 60 ticks per simulated second. Countdown and post-death resolution are excluded from this budget.'
			]),
		title: 'Exam fight list'
	};
};
var $elm$core$List$any$ = function (isOkay, list) {
	any:
	while (true) {
		if (!list.b) {
			return false;
		} else {
			var x = list.a;
			var xs = list.b;
			if (isOkay(x)) {
				return true;
			} else {
				var $temp$list = xs;
				list = $temp$list;
				continue any;
			}
		}
	}
};
var $elm$core$List$any = F2($elm$core$List$any$);
var $elm$core$List$member$ = function (x, xs) {
	return $elm$core$List$any$(
		function (a) {
			return _Utils_eq(a, x);
		},
		xs);
};
var $elm$core$List$member = F2($elm$core$List$member$);
var $author$project$Neat$Dashboard$holdTable = function (s) {
	var fights = s.champion.fights;
	var groups = $elm$core$List$foldl$(
		F2(
			function (k, acc) {
				return $elm$core$List$member$(k, acc) ? acc : _Utils_ap(
					acc,
					_List_fromArray(
						[k]));
			}),
		_List_Nil,
		$elm$core$List$map$(
			function (f) {
				return f.us + (' vs ' + f.them);
			},
			fights));
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$card),
				A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'border-radius', '12px'),
				A2($elm$html$Html$Attributes$style, 'padding', '16px 18px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '22px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'gap', '8px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
								A2($elm$html$Html$Attributes$style, 'margin', '0')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								'Exam fights  ·  saved champion from gen ' + ($elm$core$String$fromInt(s.champion.generation) + ($elm$core$List$isEmpty(s.champion.fights) ? '  ·  none yet' : '')))
							])),
						$author$project$Neat$Dashboard$infoBtn(
						$author$project$Neat$Dashboard$holdTableExplainer(s))
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
						A2($elm$html$Html$Attributes$style, 'margin', '8px 0 12px'),
						A2($elm$html$Html$Attributes$style, 'line-height', '1.45')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						'These ' + ($elm$core$String$fromInt(
							$elm$core$List$length(fights)) + ' validation fights use fixed seeds within this run. Repeated selection can overfit them; independent audits test generalization. Hover a row.'))
					])),
				$elm$core$List$isEmpty(fights) ? A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('No champion fights on status yet. Wait one generation after a trainer restart.')
					])) : A2(
				$elm$html$Html$div,
				_List_Nil,
				A2(
					$elm$core$List$cons,
					A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'display', 'grid'),
								A2($elm$html$Html$Attributes$style, 'grid-template-columns', '1.4fr 0.7fr 0.8fr 0.9fr 1.1fr'),
								A2($elm$html$Html$Attributes$style, 'gap', '8px'),
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.04em'),
								A2($elm$html$Html$Attributes$style, 'text-transform', 'uppercase'),
								A2($elm$html$Html$Attributes$style, 'padding', '0 0 6px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Our ship vs theirs')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Our seat')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Result')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Crew left')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Duration')
									]))
							])),
					$elm$core$List$concatMap$(
						function (k) {
							return $author$project$Neat$Dashboard$groupBlock$(
								k,
								$elm$core$List$filter$(
									function (f) {
										return _Utils_eq(f.us + (' vs ' + f.them), k);
									},
									fights));
						},
						groups)))
			]));
};
var $author$project$Neat$Dashboard$infoDot = A2(
	$elm$html$Html$span,
	_List_fromArray(
		[
			A2($elm$html$Html$Attributes$style, 'display', 'inline-flex'),
			A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
			A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
			A2($elm$html$Html$Attributes$style, 'width', '14px'),
			A2($elm$html$Html$Attributes$style, 'height', '14px'),
			A2($elm$html$Html$Attributes$style, 'border-radius', '50%'),
			A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$mute),
			A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
			A2($elm$html$Html$Attributes$style, 'font-size', '10px'),
			A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
			A2($elm$html$Html$Attributes$style, 'font-style', 'italic'),
			A2($elm$html$Html$Attributes$style, 'user-select', 'none')
		]),
	_List_fromArray(
		[
			$elm$html$Html$text('i')
		]));
var $author$project$Neat$Dashboard$metric$ = function (label, value, win, e) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$card),
				A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
				A2($elm$html$Html$Attributes$style, 'padding', '12px 14px'),
				A2($elm$html$Html$Attributes$style, 'cursor', 'help'),
				$elm$html$Html$Events$onMouseEnter(
				$author$project$Neat$Dashboard$ShowExplainer(e)),
				$elm$html$Html$Events$onMouseLeave($author$project$Neat$Dashboard$HideExplainer),
				$elm$html$Html$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(e))
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.04em'),
								A2($elm$html$Html$Attributes$style, 'text-transform', 'uppercase')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(label)
							])),
						$author$project$Neat$Dashboard$infoDot
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '22px'),
						A2($elm$html$Html$Attributes$style, 'font-weight', '650'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '4px'),
						A2(
						$elm$html$Html$Attributes$style,
						'color',
						win ? $author$project$Neat$Dashboard$mint : $author$project$Neat$Dashboard$ink),
						A2($elm$html$Html$Attributes$style, 'font-variant-numeric', 'tabular-nums')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(value)
					]))
			]));
};
var $author$project$Neat$Dashboard$metric = F4($author$project$Neat$Dashboard$metric$);
var $elm$core$Basics$not = _Basics_not;
var $author$project$Neat$Dashboard$matchupGrid = function (s) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$h2,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '17px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Where the champion wins and gets stuck')
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'grid'),
						A2($elm$html$Html$Attributes$style, 'grid-template-columns', 'repeat(auto-fit,minmax(220px,1fr))'),
						A2($elm$html$Html$Attributes$style, 'gap', '10px')
					]),
				$elm$core$List$concatMap$(
					function (us) {
						return $elm$core$List$map$(
							function (them) {
								var fights = $elm$core$List$filter$(
									function (f) {
										return _Utils_eq(f.us, us) && _Utils_eq(f.them, them);
									},
									s.champion.fights);
								var timeouts = $elm$core$List$length(
									$elm$core$List$filter$(
										function (f) {
											return f.outcome === 'invalidated';
										},
										fights));
								var top = $elm$core$List$length(
									$elm$core$List$filter$(
										function (f) {
											return f.swap && $author$project$Neat$Dashboard$fightWon(f);
										},
										fights));
								var wins = $elm$core$List$length(
									$elm$core$List$filter$($author$project$Neat$Dashboard$fightWon, fights));
								var bottom = $elm$core$List$length(
									$elm$core$List$filter$(
										function (f) {
											return (!f.swap) && $author$project$Neat$Dashboard$fightWon(f);
										},
										fights));
								return $author$project$Neat$Dashboard$metric$(
									us + (' vs ' + them),
									$elm$core$String$fromInt(wins) + (' / ' + $elm$core$String$fromInt(
										$elm$core$List$length(fights))),
									_Utils_eq(
										wins,
										$elm$core$List$length(fights)) && (wins > 0),
									{
										body: _List_fromArray(
											[
												'Saved validation wins. Bottom seat: ' + ($elm$core$String$fromInt(bottom) + ('. Top seat: ' + ($elm$core$String$fromInt(top) + ('. Timeouts: ' + ($elm$core$String$fromInt(timeouts) + '.'))))),
												'A zero or seat imbalance identifies a weakness. These fixed validation results are not fresh-seed evidence. Expand the fight list for crew and individual seeds.'
											]),
										title: us + (' vs ' + them)
									});
							},
							s.pool);
					},
					s.pool))
			]));
};
var $author$project$Neat$Dashboard$fmt2 = function (x) {
	return $elm$core$String$fromFloat(
		$elm$core$Basics$round(x * 100) / 100);
};
var $author$project$Neat$Dashboard$holdRecordExplainer$ = function (wins, n, _v0) {
	return {
		body: _List_fromArray(
			[
				'The saved net is tested on a fixed validation set of ' + ($elm$core$String$fromInt(n) + (' fights. Same ships, seats and set of seeds every time. Right now it has ' + ($elm$core$String$fromInt(wins) + ' kills.'))),
				'A kill means: the fight actually finished, our ship won, and the enemy has 0 crew. Timeouts and dying both count as not a kill.',
				'These fights select the champion. A separate set of fresh seeds checks the selected policy after the experiment comparison.'
			]),
		title: 'Hold record  (the number to watch)'
	};
};
var $author$project$Neat$Dashboard$holdRecordExplainer = F3($author$project$Neat$Dashboard$holdRecordExplainer$);
var $author$project$Neat$Dashboard$metrics = function (s) {
	var poolLabel = $elm$core$List$isEmpty(s.pool) ? '?' : $elm$core$String$join$(', ', s.pool);
	var holdWins = $elm$core$List$length(
		$elm$core$List$filter$($author$project$Neat$Dashboard$fightWon, s.champion.fights));
	var holdN = $elm$core$List$length(s.champion.fights);
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'display', 'grid'),
				A2($elm$html$Html$Attributes$style, 'grid-template-columns', 'repeat(auto-fit, minmax(160px, 1fr))'),
				A2($elm$html$Html$Attributes$style, 'gap', '12px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '22px')
			]),
		_List_fromArray(
			[
				$author$project$Neat$Dashboard$metric$(
				'Saved validation wins',
				$elm$core$String$fromInt(holdWins) + (' / ' + $elm$core$String$fromInt(
					$elm$core$Basics$max$(holdN, s.nHold))),
				false,
				$author$project$Neat$Dashboard$holdRecordExplainer$(
					holdWins,
					$elm$core$Basics$max$(holdN, s.nHold),
					s)),
				$author$project$Neat$Dashboard$metric$(
				'Generations since promotion',
				$elm$core$String$fromInt(
					$elm$core$Basics$max$(0, s.generation - s.champion.generation)),
				false,
				{
					body: _List_fromArray(
						['Completed generations since the saved champion was promoted. A large number means the search is active without finding a better validation policy. A promotion can improve only the fitness tiebreaker, not wins.']),
					title: 'Plateau age'
				}),
				$author$project$Neat$Dashboard$metric$(
				'Generation duration',
				$author$project$Neat$Dashboard$fmt2(s.generationS) + ' s',
				false,
				{
					body: _List_fromArray(
						['Measured time for a completed generation, including candidate evaluations and validation. This is different from a single candidate\'s evaluation time.']),
					title: 'Full generation duration'
				}),
				$author$project$Neat$Dashboard$metric$(
				'Evaluations / second',
				(s.generationS > 0) ? $author$project$Neat$Dashboard$fmt1((((s.pop + 1) * s.nTrain) + s.nHold) / s.generationS) : 'waiting',
				false,
				{
					body: _List_fromArray(
						['Candidate count times training fights, plus validation fights, divided by generation duration. Useful for capacity, not evidence of learning.']),
					title: 'Approximate fight throughput'
				})
			]));
};
var $author$project$Neat$Dashboard$netExplainer = {
	body: _List_fromArray(
		['Three columns of neurons, two layers of weights. Left: what it sees. Middle: 16 tanh hidden units. Right: turn, thrust, fire, special, plus 8 extra memory units that feed back next tick.', 'Hull identity is 5 bits for us and 5 bits for them (25 ships, so 4 bits is not enough). The hidden layer can mix those bits into ship-specific behaviour.', 'Teal = positive weight, coral = negative. Thickness is |weight|. Node colour is wiring strength, not a live fight activation.']),
	title: 'Champion net'
};
var $author$project$Neat$Dashboard$brainH = 640;
var $author$project$Neat$Dashboard$brainW = 920;
var $author$project$Neat$Dashboard$colLabel$ = function (x, txt) {
	return A2(
		$elm$svg$Svg$text_,
		_List_fromArray(
			[
				$elm$svg$Svg$Attributes$x(
				$elm$core$String$fromFloat(x)),
				$elm$svg$Svg$Attributes$y('16'),
				$elm$svg$Svg$Attributes$fill('#5f8080'),
				$elm$svg$Svg$Attributes$fontSize('11'),
				$elm$svg$Svg$Attributes$textAnchor('middle'),
				$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
			]),
		_List_fromArray(
			[
				$elm$svg$Svg$text(txt)
			]));
};
var $author$project$Neat$Dashboard$colLabel = F2($author$project$Neat$Dashboard$colLabel$);
var $author$project$Neat$Dashboard$edgeAttrs$ = function (x1, y1, x2, y2, w) {
	var width = $elm$core$Basics$max$(
		0.3,
		$elm$core$Basics$min$(
			2.8,
			$elm$core$Basics$abs(w) * 0.85));
	var a = $elm$core$Basics$max$(
		0.04,
		$elm$core$Basics$min$(
			0.8,
			$elm$core$Basics$abs(w) / 2.4));
	var color = (w >= 0) ? ('rgba(90,210,200,' + ($elm$core$String$fromFloat(a) + ')')) : ('rgba(255,110,90,' + ($elm$core$String$fromFloat(a) + ')'));
	return _List_fromArray(
		[
			$elm$svg$Svg$Attributes$x1(
			$elm$core$String$fromFloat(x1)),
			$elm$svg$Svg$Attributes$y1(
			$elm$core$String$fromFloat(y1)),
			$elm$svg$Svg$Attributes$x2(
			$elm$core$String$fromFloat(x2)),
			$elm$svg$Svg$Attributes$y2(
			$elm$core$String$fromFloat(y2)),
			$elm$svg$Svg$Attributes$stroke(color),
			$elm$svg$Svg$Attributes$strokeWidth(
			$elm$core$String$fromFloat(width))
		]);
};
var $author$project$Neat$Dashboard$edgeAttrs = F5($author$project$Neat$Dashboard$edgeAttrs$);
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightZfBy = _Bitwise_shiftRightZfBy;
var $elm$core$Array$bitMask = 4294967295 >>> (32 - $elm$core$Array$shiftStep);
var $elm$core$Elm$JsArray$unsafeGet = _JsArray_unsafeGet;
var $elm$core$Array$getHelp$ = function (shift, index, tree) {
	getHelp:
	while (true) {
		var pos = $elm$core$Array$bitMask & (index >>> shift);
		var _v0 = A2($elm$core$Elm$JsArray$unsafeGet, pos, tree);
		if (_v0.$ === 'SubTree') {
			var subTree = _v0.a;
			var $temp$shift = shift - $elm$core$Array$shiftStep,
				$temp$tree = subTree;
			shift = $temp$shift;
			tree = $temp$tree;
			continue getHelp;
		} else {
			var values = _v0.a;
			return A2($elm$core$Elm$JsArray$unsafeGet, $elm$core$Array$bitMask & index, values);
		}
	}
};
var $elm$core$Array$getHelp = F3($elm$core$Array$getHelp$);
var $elm$core$Bitwise$shiftLeftBy = _Bitwise_shiftLeftBy;
var $elm$core$Array$tailIndex = function (len) {
	return (len >>> 5) << 5;
};
var $elm$core$Array$get$ = function (index, _v0) {
	var len = _v0.a;
	var startShift = _v0.b;
	var tree = _v0.c;
	var tail = _v0.d;
	return ((index < 0) || (_Utils_cmp(index, len) > -1)) ? $elm$core$Maybe$Nothing : ((_Utils_cmp(
		index,
		$elm$core$Array$tailIndex(len)) > -1) ? $elm$core$Maybe$Just(
		A2($elm$core$Elm$JsArray$unsafeGet, $elm$core$Array$bitMask & index, tail)) : $elm$core$Maybe$Just(
		$elm$core$Array$getHelp$(startShift, index, tree)));
};
var $elm$core$Array$get = F2($elm$core$Array$get$);
var $author$project$Neat$Dashboard$w1At$ = function (n, h, i) {
	return $elm$core$Maybe$withDefault$(
		0,
		$elm$core$Array$get$((h * n.nIn) + i, n.weights));
};
var $author$project$Neat$Dashboard$w1At = F3($author$project$Neat$Dashboard$w1At$);
var $author$project$Neat$Dashboard$w2At$ = function (n, o, h) {
	return $elm$core$Maybe$withDefault$(
		0,
		$elm$core$Array$get$(((n.nHidden * n.nIn) + (o * (n.nHidden + 1))) + h, n.weights));
};
var $author$project$Neat$Dashboard$w2At = F3($author$project$Neat$Dashboard$w2At$);
var $author$project$Neat$Dashboard$hidStrength$ = function (n, h) {
	var out = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$maximum(
			$elm$core$List$map$(
				function (o) {
					return $elm$core$Basics$abs(
						$author$project$Neat$Dashboard$w2At$(n, o, h));
				},
				$elm$core$List$range$(0, n.nOut - 1))));
	var inn = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$maximum(
			$elm$core$List$map$(
				function (i) {
					return $elm$core$Basics$abs(
						$author$project$Neat$Dashboard$w1At$(n, h, i));
				},
				$elm$core$List$range$(0, n.nIn - 1))));
	return $elm$core$Basics$max$(inn, out);
};
var $author$project$Neat$Dashboard$hidStrength = F2($author$project$Neat$Dashboard$hidStrength$);
var $author$project$Neat$Dashboard$fmtW = function (w) {
	var sign = (w >= 0) ? '+' : '';
	return _Utils_ap(
		sign,
		$author$project$Neat$Dashboard$fmt2(w));
};
var $author$project$Neat$Dashboard$combatNames = _List_fromArray(
	['energy', 'crew', 'face C', 'face S', 'speed', 'travel C', 'travel S', 'weapon rdy', 'special rdy', 'turn rdy', 'thrust rdy', 'dx', 'dy', 'dist', 'closing', 'rel C', 'rel S', 'foe energy', 'foe crew', 'foe speed', 'cloaked', 'my hit', 'my soon', 'turn err', 'their hit', 'their soon', 'planet x', 'planet y', 'planet hit', 'incoming', 'in C', 'in S', 'one']);
var $author$project$Neat$Dashboard$inputNames = _Utils_ap(
	$author$project$Neat$Dashboard$combatNames,
	_Utils_ap(
		$elm$core$List$map$(
			function (i) {
				return 'us b' + $elm$core$String$fromInt(i);
			},
			$elm$core$List$range$(0, 4)),
		_Utils_ap(
			$elm$core$List$map$(
				function (i) {
					return 'them b' + $elm$core$String$fromInt(i);
				},
				$elm$core$List$range$(0, 4)),
			_List_fromArray(
				['fb L', 'fb R', 'fb thrust', 'fb fire', 'fb special', 'fb x0', 'fb x1', 'fb x2', 'fb x3', 'fb x4', 'fb x5', 'fb x6', 'fb x7', 'bias']))));
var $author$project$Neat$Dashboard$inputName = function (i) {
	return $elm$core$Maybe$withDefault$(
		'in ' + $elm$core$String$fromInt(i),
		$elm$core$List$head(
			$elm$core$List$drop$(i, $author$project$Neat$Dashboard$inputNames)));
};
var $elm$core$List$sortBy = _List_sortBy;
var $author$project$Neat$Dashboard$hiddenExplainer$ = function (n, h) {
	return {
		body: _List_fromArray(
			[
				'Tanh unit. Mixes the 5-bit hull ids with combat facts before they hit the controls.',
				'Strongest incoming: ' + ($elm$core$String$join$(
				', ',
				$elm$core$List$map$(
					function (_v1) {
						var lab = _v1.a;
						var w = _v1.b;
						return lab + (' ' + $author$project$Neat$Dashboard$fmtW(w));
					},
					$elm$core$List$take$(
						4,
						A2(
							$elm$core$List$sortBy,
							function (_v0) {
								var w = _v0.b;
								return -$elm$core$Basics$abs(w);
							},
							$elm$core$List$map$(
								function (i) {
									return _Utils_Tuple2(
										$author$project$Neat$Dashboard$inputName(i),
										$author$project$Neat$Dashboard$w1At$(n, h, i));
								},
								$elm$core$List$range$(0, n.nIn - 1)))))) + '.')
			]),
		title: 'Hidden  h' + $elm$core$String$fromInt(h)
	};
};
var $author$project$Neat$Dashboard$hiddenExplainer = F2($author$project$Neat$Dashboard$hiddenExplainer$);
var $author$project$Neat$Dashboard$nodeColor = function (v) {
	var t = $elm$core$Basics$max$(
		-1,
		$elm$core$Basics$min$(1, v));
	var mag = $elm$core$Basics$abs(t);
	var light = $elm$core$Basics$round(26 + (mag * 46));
	var hue = (t >= 0) ? 35 : 200;
	return 'hsl(' + ($elm$core$String$fromInt(hue) + (', 90%, ' + ($elm$core$String$fromInt(light) + '%)')));
};
var $elm$svg$Svg$Events$onClick = function (msg) {
	return $elm$html$Html$Events$on$(
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $author$project$Neat$Dashboard$hidNode$ = function (n, h, y) {
	var topW = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$head(
			A2(
				$elm$core$List$sortBy,
				function (w) {
					return -$elm$core$Basics$abs(w);
				},
				$elm$core$List$map$(
					function (i) {
						return $author$project$Neat$Dashboard$w1At$(n, h, i);
					},
					$elm$core$List$range$(0, n.nIn - 1)))));
	var s = $author$project$Neat$Dashboard$hidStrength$(n, h);
	var signed = (topW < 0) ? (-s) : s;
	var e = $author$project$Neat$Dashboard$hiddenExplainer$(n, h);
	return A2(
		$elm$svg$Svg$g,
		_List_fromArray(
			[
				$elm$svg$Svg$Events$onMouseOver(
				$author$project$Neat$Dashboard$ShowExplainer(e)),
				$elm$svg$Svg$Events$onMouseOut($author$project$Neat$Dashboard$HideExplainer),
				$elm$svg$Svg$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(e)),
				$elm$svg$Svg$Attributes$style('cursor:help')
			]),
		_List_fromArray(
			[
				A2(
				$elm$svg$Svg$circle,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$cx(
						$elm$core$String$fromFloat($author$project$Neat$Dashboard$brainW / 2)),
						$elm$svg$Svg$Attributes$cy(
						$elm$core$String$fromFloat(y)),
						$elm$svg$Svg$Attributes$r('5'),
						$elm$svg$Svg$Attributes$fill(
						$author$project$Neat$Dashboard$nodeColor(signed)),
						$elm$svg$Svg$Attributes$stroke('#04121a'),
						$elm$svg$Svg$Attributes$strokeWidth('1')
					]),
				_List_Nil)
			]));
};
var $author$project$Neat$Dashboard$hidNode = F3($author$project$Neat$Dashboard$hidNode$);
var $author$project$Neat$Dashboard$inStrength$ = function (n, i) {
	return $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$maximum(
			$elm$core$List$map$(
				function (h) {
					return $elm$core$Basics$abs(
						$author$project$Neat$Dashboard$w1At$(n, h, i));
				},
				$elm$core$List$range$(0, n.nHidden - 1))));
};
var $author$project$Neat$Dashboard$inStrength = F2($author$project$Neat$Dashboard$inStrength$);
var $author$project$Neat$Dashboard$topWiresHid$ = function (n, i) {
	return $elm$core$List$take$(
		4,
		A2(
			$elm$core$List$sortBy,
			function (_v0) {
				var w = _v0.b;
				return -$elm$core$Basics$abs(w);
			},
			$elm$core$List$map$(
				function (h) {
					return _Utils_Tuple2(
						'h' + $elm$core$String$fromInt(h),
						$author$project$Neat$Dashboard$w1At$(n, h, i));
				},
				$elm$core$List$range$(0, n.nHidden - 1))));
};
var $author$project$Neat$Dashboard$topWiresHid = F2($author$project$Neat$Dashboard$topWiresHid$);
var $author$project$Neat$Dashboard$inputExplainer$ = function (n, i, name) {
	return {
		body: _List_fromArray(
			[
				'Index ' + ($elm$core$String$fromInt(i) + (' of ' + ($elm$core$String$fromInt(n.nIn) + ('. Strongest wires into the hidden layer: ' + ($elm$core$String$join$(
				', ',
				$elm$core$List$map$(
					function (_v0) {
						var lab = _v0.a;
						var w = _v0.b;
						return lab + (' ' + $author$project$Neat$Dashboard$fmtW(w));
					},
					$author$project$Neat$Dashboard$topWiresHid$(n, i))) + '.')))))
			]),
		title: 'Input  ' + name
	};
};
var $author$project$Neat$Dashboard$inputExplainer = F3($author$project$Neat$Dashboard$inputExplainer$);
var $author$project$Neat$Dashboard$shouldLabelInput$ = function (i, name, _v0) {
	return ((i < 33) && (!A2($elm$core$Basics$modBy, 4, i))) || (((i >= 33) && (i <= 42)) || (((i >= 43) && (i <= 47)) || (i === 56)));
};
var $author$project$Neat$Dashboard$shouldLabelInput = F3($author$project$Neat$Dashboard$shouldLabelInput$);
var $author$project$Neat$Dashboard$inNode$ = function (n, pool, i, y, name) {
	var s = $author$project$Neat$Dashboard$inStrength$(n, i);
	var signed = function () {
		var top = $elm$core$Maybe$withDefault$(
			0,
			$elm$core$List$head(
				A2(
					$elm$core$List$sortBy,
					function (w) {
						return -$elm$core$Basics$abs(w);
					},
					$elm$core$List$map$(
						function (h) {
							return $author$project$Neat$Dashboard$w1At$(n, h, i);
						},
						$elm$core$List$range$(0, n.nHidden - 1)))));
		return (top < 0) ? (-s) : s;
	}();
	var hot = A2($elm$core$String$startsWith, 'us ', name) || A2($elm$core$String$startsWith, 'them ', name);
	var e = $author$project$Neat$Dashboard$inputExplainer$(n, i, name);
	return A2(
		$elm$svg$Svg$g,
		_List_fromArray(
			[
				$elm$svg$Svg$Events$onMouseOver(
				$author$project$Neat$Dashboard$ShowExplainer(e)),
				$elm$svg$Svg$Events$onMouseOut($author$project$Neat$Dashboard$HideExplainer),
				$elm$svg$Svg$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(e)),
				$elm$svg$Svg$Attributes$style('cursor:help')
			]),
		_List_fromArray(
			[
				A2(
				$elm$svg$Svg$circle,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$cx('110'),
						$elm$svg$Svg$Attributes$cy(
						$elm$core$String$fromFloat(y)),
						$elm$svg$Svg$Attributes$r(
						hot ? '3.4' : '2.3'),
						$elm$svg$Svg$Attributes$fill(
						$author$project$Neat$Dashboard$nodeColor(signed)),
						$elm$svg$Svg$Attributes$stroke(
						hot ? $author$project$Neat$Dashboard$gold : '#04121a'),
						$elm$svg$Svg$Attributes$strokeWidth('1')
					]),
				_List_Nil),
				$author$project$Neat$Dashboard$shouldLabelInput$(i, name, pool) ? A2(
				$elm$svg$Svg$text_,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$x('100'),
						$elm$svg$Svg$Attributes$y(
						$elm$core$String$fromFloat(y + 3)),
						$elm$svg$Svg$Attributes$fill('#8fb2b2'),
						$elm$svg$Svg$Attributes$fontSize('8'),
						$elm$svg$Svg$Attributes$textAnchor('end'),
						$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
					]),
				_List_fromArray(
					[
						$elm$svg$Svg$text(name)
					])) : $elm$svg$Svg$text('')
			]));
};
var $author$project$Neat$Dashboard$inNode = F5($author$project$Neat$Dashboard$inNode$);
var $author$project$Neat$Dashboard$groupTag$ = function (y, txt) {
	return A2(
		$elm$svg$Svg$text_,
		_List_fromArray(
			[
				$elm$svg$Svg$Attributes$x('8'),
				$elm$svg$Svg$Attributes$y(
				$elm$core$String$fromFloat(y + 3)),
				$elm$svg$Svg$Attributes$fill('#5f8080'),
				$elm$svg$Svg$Attributes$fontSize('10'),
				$elm$svg$Svg$Attributes$textAnchor('start'),
				$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
			]),
		_List_fromArray(
			[
				$elm$svg$Svg$text(txt)
			]));
};
var $author$project$Neat$Dashboard$groupTag = F2($author$project$Neat$Dashboard$groupTag$);
var $author$project$Neat$Dashboard$nodeYs = function (n) {
	var top = 28;
	var bottom = $author$project$Neat$Dashboard$brainH - 16;
	var gap = (n <= 1) ? 0 : ((bottom - top) / (n - 1));
	return $elm$core$List$map$(
		function (i) {
			return top + (gap * i);
		},
		$elm$core$List$range$(0, n - 1));
};
var $author$project$Neat$Dashboard$ysAt = function (i) {
	return $elm$core$Maybe$withDefault$(
		28,
		$elm$core$List$head(
			$elm$core$List$drop$(
				i,
				$author$project$Neat$Dashboard$nodeYs(57))));
};
var $author$project$Neat$Dashboard$inputGroupLabels = _List_fromArray(
	[
		$author$project$Neat$Dashboard$groupTag$(28, 'combat'),
		$author$project$Neat$Dashboard$groupTag$(
		$author$project$Neat$Dashboard$ysAt(33),
		'us bits'),
		$author$project$Neat$Dashboard$groupTag$(
		$author$project$Neat$Dashboard$ysAt(38),
		'them bits'),
		$author$project$Neat$Dashboard$groupTag$(
		$author$project$Neat$Dashboard$ysAt(43),
		'last tick'),
		$author$project$Neat$Dashboard$groupTag$(
		$author$project$Neat$Dashboard$ysAt(56),
		'bias')
	]);
var $elm$core$List$map3 = _List_map3;
var $author$project$Neat$Dashboard$outStrength$ = function (n, o) {
	return $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$maximum(
			$elm$core$List$map$(
				function (h) {
					return $elm$core$Basics$abs(
						$author$project$Neat$Dashboard$w2At$(n, o, h));
				},
				$elm$core$List$range$(0, n.nHidden - 1))));
};
var $author$project$Neat$Dashboard$outStrength = F2($author$project$Neat$Dashboard$outStrength$);
var $author$project$Neat$Dashboard$topWiresIn$ = function (n, o) {
	return $elm$core$List$take$(
		5,
		A2(
			$elm$core$List$sortBy,
			function (_v0) {
				var w = _v0.b;
				return -$elm$core$Basics$abs(w);
			},
			$elm$core$List$map$(
				function (h) {
					return _Utils_Tuple2(
						'h' + $elm$core$String$fromInt(h),
						$author$project$Neat$Dashboard$w2At$(n, o, h));
				},
				$elm$core$List$range$(0, n.nHidden - 1))));
};
var $author$project$Neat$Dashboard$topWiresIn = F2($author$project$Neat$Dashboard$topWiresIn$);
var $author$project$Neat$Dashboard$outputExplainer$ = function (n, o, name) {
	return {
		body: _List_fromArray(
			[
				(o < 5) ? 'Control bit. Fires when this output is above 0.' : 'Extra memory unit. Tanh, then fed back as input next tick. Not a button.',
				'Strongest wires from hidden: ' + ($elm$core$String$join$(
				', ',
				$elm$core$List$map$(
					function (_v0) {
						var lab = _v0.a;
						var w = _v0.b;
						return lab + (' ' + $author$project$Neat$Dashboard$fmtW(w));
					},
					$author$project$Neat$Dashboard$topWiresIn$(n, o))) + '.')
			]),
		title: 'Output  ' + name
	};
};
var $author$project$Neat$Dashboard$outputExplainer = F3($author$project$Neat$Dashboard$outputExplainer$);
var $author$project$Neat$Dashboard$outNode$ = function (n, o, y, name) {
	var topW = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$head(
			A2(
				$elm$core$List$sortBy,
				function (w) {
					return -$elm$core$Basics$abs(w);
				},
				$elm$core$List$map$(
					function (h) {
						return $author$project$Neat$Dashboard$w2At$(n, o, h);
					},
					$elm$core$List$range$(0, n.nHidden - 1)))));
	var s = $author$project$Neat$Dashboard$outStrength$(n, o);
	var signed = (topW < 0) ? (-s) : s;
	var e = $author$project$Neat$Dashboard$outputExplainer$(n, o, name);
	return A2(
		$elm$svg$Svg$g,
		_List_fromArray(
			[
				$elm$svg$Svg$Events$onMouseOver(
				$author$project$Neat$Dashboard$ShowExplainer(e)),
				$elm$svg$Svg$Events$onMouseOut($author$project$Neat$Dashboard$HideExplainer),
				$elm$svg$Svg$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(e)),
				$elm$svg$Svg$Attributes$style('cursor:help')
			]),
		_List_fromArray(
			[
				A2(
				$elm$svg$Svg$circle,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$cx(
						$elm$core$String$fromFloat($author$project$Neat$Dashboard$brainW - 70)),
						$elm$svg$Svg$Attributes$cy(
						$elm$core$String$fromFloat(y)),
						$elm$svg$Svg$Attributes$r('6'),
						$elm$svg$Svg$Attributes$fill(
						$author$project$Neat$Dashboard$nodeColor(signed)),
						$elm$svg$Svg$Attributes$stroke('#04121a'),
						$elm$svg$Svg$Attributes$strokeWidth('1')
					]),
				_List_Nil),
				A2(
				$elm$svg$Svg$text_,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$x(
						$elm$core$String$fromFloat($author$project$Neat$Dashboard$brainW - 58)),
						$elm$svg$Svg$Attributes$y(
						$elm$core$String$fromFloat(y + 3.5)),
						$elm$svg$Svg$Attributes$fill('#cfe8e6'),
						$elm$svg$Svg$Attributes$fontSize('11'),
						$elm$svg$Svg$Attributes$textAnchor('start'),
						$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
					]),
				_List_fromArray(
					[
						$elm$svg$Svg$text(name)
					]))
			]));
};
var $author$project$Neat$Dashboard$outNode = F4($author$project$Neat$Dashboard$outNode$);
var $author$project$Neat$Dashboard$outputNames = _List_fromArray(
	['turn L', 'turn R', 'thrust', 'fire', 'special', 'extra 0', 'extra 1', 'extra 2', 'extra 3', 'extra 4', 'extra 5', 'extra 6', 'extra 7']);
var $elm$svg$Svg$Attributes$preserveAspectRatio = _VirtualDom_attribute('preserveAspectRatio');
var $author$project$Neat$Dashboard$viewBrain$ = function (n, pool) {
	var outs = $author$project$Neat$Dashboard$outputNames;
	var outYs = $author$project$Neat$Dashboard$nodeYs(n.nOut);
	var outX = $author$project$Neat$Dashboard$brainW - 70;
	var outNodes = A4(
		$elm$core$List$map3,
		F3(
			function (o, y, name) {
				return $author$project$Neat$Dashboard$outNode$(n, o, y, name);
			}),
		$elm$core$List$range$(0, n.nOut - 1),
		outYs,
		outs);
	var ins = $author$project$Neat$Dashboard$inputNames;
	var inYs = $author$project$Neat$Dashboard$nodeYs(n.nIn);
	var inX = 110;
	var inNodes = A4(
		$elm$core$List$map3,
		F3(
			function (i, y, name) {
				return $author$project$Neat$Dashboard$inNode$(n, pool, i, y, name);
			}),
		$elm$core$List$range$(0, n.nIn - 1),
		inYs,
		ins);
	var hidYs = $author$project$Neat$Dashboard$nodeYs(n.nHidden);
	var hidX = $author$project$Neat$Dashboard$brainW / 2;
	var hidNodes = $elm$core$List$indexedMap$(
		F2(
			function (h, y) {
				return $author$project$Neat$Dashboard$hidNode$(n, h, y);
			}),
		hidYs);
	var groups = $author$project$Neat$Dashboard$inputGroupLabels;
	var edges2 = $elm$core$List$concat(
		$elm$core$List$indexedMap$(
			F2(
				function (o, toY) {
					return $elm$core$List$indexedMap$(
						F2(
							function (h, fromY) {
								return A2(
									$elm$svg$Svg$line,
									$author$project$Neat$Dashboard$edgeAttrs$(
										hidX,
										fromY,
										outX,
										toY,
										$author$project$Neat$Dashboard$w2At$(n, o, h)),
									_List_Nil);
							}),
						hidYs);
				}),
			outYs));
	var edges1 = $elm$core$List$concat(
		$elm$core$List$indexedMap$(
			F2(
				function (h, toY) {
					return $elm$core$List$indexedMap$(
						F2(
							function (i, fromY) {
								return A2(
									$elm$svg$Svg$line,
									$author$project$Neat$Dashboard$edgeAttrs$(
										inX,
										fromY,
										hidX,
										toY,
										$author$project$Neat$Dashboard$w1At$(n, h, i)),
									_List_Nil);
							}),
						inYs);
				}),
			hidYs));
	var colLabs = _List_fromArray(
		[
			$author$project$Neat$Dashboard$colLabel$(inX, 'inputs'),
			$author$project$Neat$Dashboard$colLabel$(hidX, 'hidden'),
			$author$project$Neat$Dashboard$colLabel$(outX, 'outputs')
		]);
	return A2(
		$elm$svg$Svg$svg,
		_List_fromArray(
			[
				$elm$svg$Svg$Attributes$viewBox(
				'0 0 ' + ($elm$core$String$fromFloat($author$project$Neat$Dashboard$brainW) + (' ' + $elm$core$String$fromFloat($author$project$Neat$Dashboard$brainH)))),
				$elm$svg$Svg$Attributes$preserveAspectRatio('xMidYMid meet'),
				$elm$svg$Svg$Attributes$width('100%'),
				$elm$svg$Svg$Attributes$height('100%'),
				$elm$svg$Svg$Attributes$style('display:block; background:#071019; border-radius:8px;')
			]),
		_Utils_ap(
			edges1,
			_Utils_ap(
				edges2,
				_Utils_ap(
					groups,
					_Utils_ap(
						colLabs,
						_Utils_ap(
							inNodes,
							_Utils_ap(hidNodes, outNodes)))))));
};
var $author$project$Neat$Dashboard$viewBrain = F2($author$project$Neat$Dashboard$viewBrain$);
var $author$project$Neat$Dashboard$netCard$ = function (model, s) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$card),
				A2($elm$html$Html$Attributes$style, 'border', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'border-radius', '12px'),
				A2($elm$html$Html$Attributes$style, 'padding', '16px 16px 10px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '22px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'gap', '8px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
								A2($elm$html$Html$Attributes$style, 'margin', '0'),
								A2($elm$html$Html$Attributes$style, 'font-weight', '650')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								'Champion net  ·  gen ' + function () {
									var _v0 = model.net;
									if (_v0.$ === 'Just') {
										var n = _v0.a;
										return $elm$core$String$fromInt(n.generation);
									} else {
										return $elm$core$String$fromInt(s.champion.generation);
									}
								}())
							])),
						$author$project$Neat$Dashboard$infoBtn($author$project$Neat$Dashboard$netExplainer)
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
						A2($elm$html$Html$Attributes$style, 'margin', '8px 0 12px'),
						A2($elm$html$Html$Attributes$style, 'line-height', '1.45')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Two weight layers: inputs to 16 hidden tanh units to 13 outputs. Teal positive, coral negative. Hover a node.')
					])),
				function () {
				var _v1 = model.net;
				if (_v1.$ === 'Nothing') {
					return A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Loading champion weights.')
							]));
				} else {
					var n = _v1.a;
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'height', '640px')
							]),
						_List_fromArray(
							[
								$author$project$Neat$Dashboard$viewBrain$(n, s.pool)
							]));
				}
			}()
			]));
};
var $author$project$Neat$Dashboard$netCard = F2($author$project$Neat$Dashboard$netCard$);
var $author$project$Neat$Dashboard$reviewRow = function (r) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'padding', '12px 0'),
				A2($elm$html$Html$Attributes$style, 'border-top', '1px solid ' + $author$project$Neat$Dashboard$line),
				A2($elm$html$Html$Attributes$style, 'cursor', 'help'),
				$elm$html$Html$Events$onMouseEnter(
				$author$project$Neat$Dashboard$ShowExplainer(
					{
						body: A2(
							$elm$core$List$cons,
							r.hypothesis,
							_Utils_ap(
								r._arguments,
								_List_fromArray(
									['Fresh audit seeds are never used for training. The comparison uses the same fight budget. A rejected result is retained as evidence.']))),
						title: 'Experiment ' + $elm$core$String$fromInt(r.cycle + 1)
					})),
				$elm$html$Html$Events$onMouseLeave($author$project$Neat$Dashboard$HideExplainer),
				$elm$html$Html$Events$onClick(
				$author$project$Neat$Dashboard$PinExplainer(
					{
						body: A2($elm$core$List$cons, r.hypothesis, r._arguments),
						title: r.lane + ' experiment'
					}))
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$Attributes$style,
						'color',
						(r.decision === 'deployed') ? $author$project$Neat$Dashboard$mint : $author$project$Neat$Dashboard$mute)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						'#' + ($elm$core$String$fromInt(r.cycle + 1) + (' · ' + (r.lane + (' · ' + r.decision)))))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'margin-top', '5px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						(!r.fights) ? 'No completed audit' : ('Baseline ' + ($elm$core$String$fromInt(r.baseline) + (' → challenger ' + ($elm$core$String$fromInt(r.challenger) + (' wins / ' + ($elm$core$String$fromInt(r.fights) + ' fresh fights')))))))
					]))
			]));
};
var $author$project$Neat$Dashboard$reviewCard = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$card),
				A2($elm$html$Html$Attributes$style, 'padding', '18px'),
				A2($elm$html$Html$Attributes$style, 'border-radius', '12px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$h2,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '17px'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Is the policy actually improving?')
					])),
				(model.reviewError !== '') ? A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$coral)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Review monitor unavailable: ' + model.reviewError)
					])) : $elm$html$Html$text(''),
				function () {
				var _v0 = model.review;
				if (_v0.$ === 'Nothing') {
					return $elm$html$Html$text('Waiting for the independent review monitor.');
				} else {
					var r = _v0.a;
					return A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'display', 'grid'),
										A2($elm$html$Html$Attributes$style, 'grid-template-columns', 'repeat(auto-fit,minmax(180px,1fr))'),
										A2($elm$html$Html$Attributes$style, 'gap', '12px')
									]),
								_List_fromArray(
									[
										$author$project$Neat$Dashboard$metric$(
										'Training health',
										(!r.active) ? 'STOPPED' : ((r.age > 30) ? 'STALE' : 'LIVE'),
										r.active && (r.age <= 30),
										{
											body: _List_fromArray(
												[
													'Checks the actual service and status file age. Last status write was ' + ($author$project$Neat$Dashboard$fmt1(r.age) + ' seconds ago. A stale file is not live progress.')
												]),
											title: 'Training health'
										}),
										$author$project$Neat$Dashboard$metric$(
										'Review cycle',
										r.lane + (' / ' + r.phase),
										false,
										{
											body: _List_fromArray(
												['Research, creative, radical, one turn each. These are programmed recipes with changing seeds and parameters, not an autonomous LLM reading new papers.']),
											title: 'Equal experiment lanes'
										}),
										$author$project$Neat$Dashboard$metric$(
										'Next scheduled review',
										(r.next <= 0) ? 'pending' : ((_Utils_cmp(r.next, r.now) < 1) ? 'due / running' : $author$project$Neat$Dashboard$uptime(r.next - r.now)),
										false,
										{
											body: _List_fromArray(
												['New experiments run hourly, with automated health checks every 15 minutes. Trials get a 40-generation screening checkpoint before the full 160-generation comparison. Only independently confirmed gains deploy.']),
											title: 'Hourly experiments, frequent checks'
										})
									])),
								A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'line-height', '1.5')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(r.hypothesis)
									])),
								((r.phase === 'baseline') || (r.phase === 'challenger')) ? A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										r.phase + (': generation ' + ($elm$core$String$fromInt(r.trialGeneration) + (' / ' + ($elm$core$String$fromInt(r.targetGenerations) + '. Both arms get the same fight budget.')))))
									])) : $elm$html$Html$text(''),
								((r.screen !== '') && (r.phase !== 'waiting')) ? A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$gold)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(r.screen)
									])) : $elm$html$Html$text(''),
								A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute),
										A2($elm$html$Html$Attributes$style, 'font-size', '13px')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Keep rule: at least 8 extra wins on 360 fresh fights, then beat the baseline and live champion on another 360. Failed ideas stay in the ledger; the live champion stays protected.')
									])),
								(r.freshCheck !== '') ? A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$ink)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(r.freshCheck)
									])) : $elm$html$Html$text(''),
								(r.error !== '') ? A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$coral)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(r.error)
									])) : $elm$html$Html$text(''),
								$elm$core$List$isEmpty(r.history) ? A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('No completed reviews yet. Fresh-seed improvement has not been demonstrated.')
									])) : A2(
								$elm$html$Html$div,
								_List_Nil,
								$elm$core$List$map$(
									$author$project$Neat$Dashboard$reviewRow,
									$elm$core$List$take$(
										12,
										$elm$core$List$reverse(r.history))))
							]));
				}
			}()
			]));
};
var $elm$html$Html$summary = _VirtualDom_node('summary');
var $author$project$Neat$Dashboard$view = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'min-height', '100vh'),
				A2($elm$html$Html$Attributes$style, 'background', $author$project$Neat$Dashboard$bg),
				A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$ink),
				A2($elm$html$Html$Attributes$style, 'font-family', 'ui-sans-serif, system-ui, sans-serif'),
				A2($elm$html$Html$Attributes$style, 'padding', '24px 20px 48px'),
				A2($elm$html$Html$Attributes$style, 'max-width', '1100px'),
				A2($elm$html$Html$Attributes$style, 'margin', '0 auto')
			]),
		_List_fromArray(
			[
				$author$project$Neat$Dashboard$header(model),
				$author$project$Neat$Dashboard$hintBar(model),
				function () {
				var _v0 = model.status;
				if (_v0.$ === 'Nothing') {
					return A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$mute)
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$elm$core$Maybe$withDefault$('Waiting for the trainer.', model.err))
							]));
				} else {
					var s = _v0.a;
					return A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								$author$project$Neat$Dashboard$metrics(s),
								$author$project$Neat$Dashboard$reviewCard(model),
								$author$project$Neat$Dashboard$matchupGrid(s),
								$author$project$Neat$Dashboard$charts$(model, s),
								A2(
								$elm$html$Html$details,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'margin', '20px 0')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$summary,
										_List_fromArray(
											[
												A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
												A2($elm$html$Html$Attributes$style, 'padding', '14px')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												$elm$core$String$fromInt(
													$elm$core$List$length(s.champion.fights)) + ' validation fights: seeds, seats, crew and outcomes')
											])),
										$author$project$Neat$Dashboard$holdTable(s)
									])),
								A2(
								$elm$html$Html$details,
								_List_Nil,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$summary,
										_List_fromArray(
											[
												A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
												A2($elm$html$Html$Attributes$style, 'padding', '14px')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Explore the saved neural network')
											])),
										$author$project$Neat$Dashboard$netCard$(model, s)
									]))
							]));
				}
			}(),
				function () {
				var _v1 = model.err;
				if (_v1.$ === 'Just') {
					var e = _v1.a;
					return A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', $author$project$Neat$Dashboard$coral),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(e)
							]));
				} else {
					return $elm$html$Html$text('');
				}
			}(),
				$author$project$Neat$Dashboard$explainerModal(model)
			]));
};
var $author$project$Neat$Dashboard$main = $elm$browser$Browser$element(
	{
		init: function (_v0) {
			return _Utils_Tuple2(
				$author$project$Neat$Dashboard$init,
				$elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[$author$project$Neat$Dashboard$fetch, $author$project$Neat$Dashboard$fetchNet, $author$project$Neat$Dashboard$fetchReview])));
		},
		subscriptions: function (_v1) {
			return $elm$time$Time$every$(2000, $author$project$Neat$Dashboard$Tick);
		},
		update: $author$project$Neat$Dashboard$update,
		view: $author$project$Neat$Dashboard$view
	});
_Platform_export({'Neat':{'Dashboard':{'init':$author$project$Neat$Dashboard$main(
	$elm$json$Json$Decode$succeed(_Utils_Tuple0))(0)}}});function _Debug_toAnsiString(ansi, value)
{
  if (typeof value === 'function')
  {
    return _Debug_internalColor(ansi, '<function>');
  }

  if (typeof value === 'boolean')
  {
    return _Debug_ctorColor(ansi, value ? 'True' : 'False');
  }

  if (typeof value === 'number')
  {
    return _Debug_numberColor(ansi, value + '');
  }

  if (value instanceof String)
  {
    return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
  }

  if (typeof value === 'string')
  {
    return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
  }

  if (typeof value === 'object' && '$' in value)
  {
    var tag = value.$;

    if (typeof tag === 'number')
    {
      return _Debug_internalColor(ansi, '<internals>');
    }

    if (tag[0] === '#')
    {
      var output = [];
      for (var k in value)
      {
        if (k === '$') continue;
        output.push(_Debug_toAnsiString(ansi, value[k]));
      }
      return '(' + output.join(',') + ')';
    }

    if (tag === 'Set_elm_builtin')
    {
      return _Debug_ctorColor(ansi, 'Set')
        + _Debug_fadeColor(ansi, '.fromList') + ' '
        + _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
    }

    if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
    {
      return _Debug_ctorColor(ansi, 'Dict')
        + _Debug_fadeColor(ansi, '.fromList') + ' '
        + _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
    }

    if (tag === 'SeqSet_elm_builtin')
    {
      return _Debug_ctorColor(ansi, 'SeqSet')
        + _Debug_fadeColor(ansi, '.fromList') + ' '
        + _Debug_toAnsiString(ansi, $lamdera$containers$SeqSet$toList(value));
    }

    if (tag === 'SeqDict_elm_builtin')
    {
      return _Debug_ctorColor(ansi, 'SeqDict')
        + _Debug_fadeColor(ansi, '.fromList') + ' '
        + _Debug_toAnsiString(ansi, $lamdera$containers$SeqDict$toList(value));
    }

    if (tag === 'Array_elm_builtin')
    {
      return _Debug_ctorColor(ansi, 'Array')
        + _Debug_fadeColor(ansi, '.fromList') + ' '
        + _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
    }

    if (tag === '::' || tag === '[]')
    {
      var output = '[';

      value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

      for (; value.b; value = value.b) // WHILE_CONS
      {
        output += ',' + _Debug_toAnsiString(ansi, value.a);
      }
      return output + ']';
    }

    var output = '';
    for (var i in value)
    {
      if (i === '$') continue;
      var str = _Debug_toAnsiString(ansi, value[i]);
      var c0 = str[0];
      var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
      output += ' ' + (parenless ? str : '(' + str + ')');
    }
    return _Debug_ctorColor(ansi, tag) + output;
  }

  if (typeof DataView === 'function' && value instanceof DataView)
  {
    return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
  }

  if (typeof File !== 'undefined' && value instanceof File)
  {
    return _Debug_internalColor(ansi, '<' + value.name + '>');
  }

  if (typeof value === 'object')
  {
    var output = [];
    for (var key in value)
    {
      var field = key[0] === '_' ? key.slice(1) : key;
      output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
    }
    if (output.length === 0)
    {
      return '{}';
    }
    return '{ ' + output.join(', ') + ' }';
  }

  return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
  var s = str
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/\t/g, '\\t')
    .replace(/\r/g, '\\r')
    .replace(/\v/g, '\\v')
    .replace(/\0/g, '\\0');

  if (isChar)
  {
    return s.replace(/\'/g, '\\\'');
  }
  else
  {
    return s.replace(/\"/g, '\\"');
  }
}

function _Utils_eqHelp(x, y, depth, stack)
{
  if (x === y)
  {
    return true;
  }

  if (typeof x !== 'object' || x === null || y === null)
  {
    typeof x === 'function' && $elm$core$Debug$crash(5);
    return false;
  }

  if (depth > 100)
  {
    stack.push(_Utils_Tuple2(x,y));
    return true;
  }

  if (x.$ === 'Set_elm_builtin')
{
  x = $elm$core$Set$toList(x);
  y = $elm$core$Set$toList(y);
}
if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
{
  x = $elm$core$Dict$toList(x);
  y = $elm$core$Dict$toList(y);
}
if (x.$ === 'SeqDict_elm_builtin')
{
  x = $lamdera$containers$SeqDict$toList(x);
  y = $lamdera$containers$SeqDict$toList(y);
}
if (x.$ === 'SeqSet_elm_builtin')
{
  x = $lamdera$containers$SeqSet$toList(x);
  y = $lamdera$containers$SeqSet$toList(y);
}

  for (var key in x)
  {
    if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
    {
      return false;
    }
  }
  return true;
}

function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
  {
    var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));

    // @TODO need to figure out how to get this to automatically escape by mode?
    //$elm$core$Result$isOk(result) || _Debug_crash(2 /**/, _Json_errorToString(result.a) /**/);
    $elm$core$Result$isOk(result) || _Debug_crash(2 /**_UNUSED/, _Json_errorToString(result.a) /**/);

    var managers = {};
    var initPair = init(result.a);
    var model = (args && args['model']) || initPair.a;

    var stepper = stepperBuilder(sendToApp, model);
    var ports = _Platform_setupEffects(managers, sendToApp);

    var upgradeMode = false;

    var errorHandler = args && args['errorHandler'];

    function sendToApp(msg, viewMetadata)
    {
      if (upgradeMode) {
        // No more messages should run in upgrade mode
        _Platform_enqueueEffects(managers, $elm$core$Platform$Cmd$none, $elm$core$Platform$Sub$none);
        return;
      }

      try {
        var pair = A2(update, msg, model);
        stepper(model = pair.a, viewMetadata);
        _Platform_enqueueEffects(managers, pair.b, subscriptions(model));
      } catch (e) {
        if (errorHandler !== undefined) { errorHandler(e) } else { throw e }
      }
    }

    if ((args && args['model']) === undefined) {
      _Platform_enqueueEffects(managers, initPair.b, subscriptions(model));
    }

    const die = function() {
      // Stop all subscriptions.
      // This must be done before clearing the stuff below.
      _Platform_enqueueEffects(managers, _Platform_batch(_List_Nil), _Platform_batch(_List_Nil));

      managers = null;
      model = null;
      stepper = null;
      ports = null;
      _Platform_effectsQueue = [];
    }

    return ports ? {
      ports: ports,
      gm: function() { return model },
      eum: function() { upgradeMode = true },
      die: die,
      fns: {}
    } : {};
  }}(this));
const pkgExports = {
'melee-browser.js': function(exports){
/* elm-pkg-js
import Json.Encode
port melee_browser_to_js : Json.Encode.Value -> Cmd msg
port melee_browser_from_js : (Json.Encode.Value -> msg) -> Sub msg
*/
exports.init = async function(app) {
  window.__uqmBrowserDispose?.();
  const send = value => app.ports.melee_browser_from_js?.send(value);
  const ids = new WeakMap(); let serial=0;
  const identify = element => { if (!element) return ""; if (!ids.has(element)) { ids.set(element, String(++serial)); element.dataset.meleeFocus=ids.get(element); } return ids.get(element); };
  const describe = element => { const r=element.getBoundingClientRect(); return {id:identify(element),label:element.getAttribute("aria-label")||element.textContent.trim(),x:r.x+r.width/2,y:r.y+r.height/2}; };
  const channels = new Map();
  const onCommand = command => {
    const target = command.id ? document.querySelector(`[data-melee-focus="${CSS.escape(command.id)}"]`) : null;
    switch(command.op) {
      case "focus": target?.focus({preventScroll:true}); break;
      case "activate": target?.click(); break;
      case "blur": document.activeElement?.blur(); break;
      case "stop": channels.get(command.channel)?.pause(); break;
      case "play": {
        channels.get(command.channel)?.pause();
        const audio=new Audio(command.src); audio.volume=command.volume;
        channels.set(command.channel,audio); audio.play().catch(()=>{}); break;
      }
    }
  };
  app.ports.melee_browser_to_js?.subscribe(onCommand);
  const onKey = event => {
    const root=document.getElementById("melee-game"), active=document.activeElement;
    if (!root || root.dataset.inputMode!=="menu" || event.altKey || event.ctrlKey || event.metaKey || (active!==document.body && !root.contains(active))) return;
    const editing=!!active?.matches("input,select,textarea");
    if ((!event.key.startsWith("Arrow") && event.key!=="Escape") || (editing && event.key!=="Escape")) return;
    event.preventDefault();event.stopPropagation();
    const nodes=[...root.querySelectorAll("button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled)")].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&getComputedStyle(e).visibility!=="hidden";}).map(describe);
    send({event:"key",key:event.key,active:identify(active),editing,nodes});
  };
  const onClick = event => {
    const root=document.getElementById("melee-game"),target=event.target.closest("button,a");
    if (root && target && root.contains(target) && root.dataset.playing!=="true") send({event:"click",label:target.getAttribute("aria-label")||target.textContent.trim()});
  };
  document.addEventListener("keydown",onKey,true);
  document.addEventListener("click",onClick);
  window.__uqmBrowserDispose = () => {
    document.removeEventListener("keydown",onKey,true);
    document.removeEventListener("click",onClick);
    app.ports.melee_browser_to_js?.unsubscribe(onCommand);
    channels.forEach(audio=>audio.pause());
  };
};

return exports;},
'telemetry.js': function(exports){
/* elm-pkg-js
port telemetry_read : ( Int, Bool ) -> Cmd msg
import Json.Encode
port telemetry_observed : (Json.Encode.Value -> msg) -> Sub msg
*/
exports.init = async function(app) {
  window.__uqmTelemetryDispose?.();
  const read = ([serial, returning]) => app.ports.telemetry_observed?.send([serial, returning, performance.now()]);
  app.ports.telemetry_read?.subscribe(read);
  window.__uqmTelemetryDispose = () => app.ports.telemetry_read?.unsubscribe(read);
};

return exports;},
'melee-music.js': function(exports){
exports.init = async function () {
// Browser playback only; Elm owns track selection, pause and sound settings.
class UqmMusic extends HTMLElement {
  static observedAttributes = ["src", "playing", "muted", "loop"];
  constructor() {
    super();
    this.audio = new Audio();
    this.audio.volume = 0.35;
    this.audio.preload = "auto";
    this.unlock = () => this.sync();
  }
  connectedCallback() {
    document.addEventListener("pointerdown", this.unlock);
    document.addEventListener("keydown", this.unlock);
    this.sync();
  }
  disconnectedCallback() {
    this.audio.pause();
    document.removeEventListener("pointerdown", this.unlock);
    document.removeEventListener("keydown", this.unlock);
  }
  attributeChangedCallback() { if (this.isConnected) this.sync(); }
  sync() {
    const src = this.getAttribute("src") || "";
    this.audio.muted = this.getAttribute("muted") === "true";
    this.audio.loop = this.getAttribute("loop") === "true";
    if (this.track !== src) {
      this.track = src;
      this.audio.pause();
      if (src) this.audio.src = src;
      else { this.audio.removeAttribute("src"); this.audio.load(); }
    }
    if (src && this.getAttribute("playing") === "true") {
      if (this.audio.paused && !(this.audio.ended && !this.audio.loop)) this.audio.play().catch(() => {});
    } else this.audio.pause();
  }
}
if (!customElements.get("uqm-music")) customElements.define("uqm-music", UqmMusic);

};

return exports;},
'clipboard.js': function(exports){
/* elm-pkg-js
import Json.Encode
port clipboard_to_js : Json.Encode.Value -> Cmd msg
port clipboard_from_js : (Json.Encode.Value -> msg) -> Sub msg
*/

exports.init = async function (app) {
    // Subscribe to copy-to-clipboard requests from Elm
    if (app.ports.clipboard_to_js) {
        app.ports.clipboard_to_js.subscribe(async function(text) {
            try {
                // Use the modern Clipboard API
                await navigator.clipboard.writeText(text);
                
                // Send success message back to Elm
                if (app.ports.clipboard_from_js) {
                    app.ports.clipboard_from_js.send("Copied to clipboard!");
                }
            } catch (err) {
                console.error('Failed to copy to clipboard:', err);
                
                // Send error message back to Elm
                if (app.ports.clipboard_from_js) {
                    app.ports.clipboard_from_js.send("Failed to copy: " + err.message);
                }
            }
        });
    }
}
return exports;},
'console-logger.js': function(exports){
/* elm-pkg-js
import Json.Encode
port console_logger_to_js : Json.Encode.Value -> Cmd msg
port console_logger_from_js : (Json.Encode.Value -> msg) -> Sub msg
*/

exports.init = async function (app) {
    // Subscribe to messages from Elm
    if (app.ports.console_logger_to_js) {
        app.ports.console_logger_to_js.subscribe(function(message) {
            // Log the message to the console
            console.log("[Elm Console Logger]:", message);
            
            // Send a confirmation back to Elm
            if (app.ports.console_logger_from_js) {
                app.ports.console_logger_from_js.send("Logged: " + message);
            }
        });
    }
}
return exports;},

}
if (typeof window !== 'undefined') {  window.elmPkgJsIncludes = {    init: async function(app) {      for (var pkgId in pkgExports) {        if (pkgExports.hasOwnProperty(pkgId)) {          pkgExports[pkgId]({}).init(app)        }      }    }  }}
