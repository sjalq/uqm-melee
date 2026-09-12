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

	/**_UNUSED/
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

	/**/
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

	/**_UNUSED/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**/
	if (typeof x.$ === 'undefined')
	//*/
	/**_UNUSED/
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

var _Utils_Tuple0 = 0;
var _Utils_Tuple0_UNUSED = { $: '#0' };

function _Utils_Tuple2(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2_UNUSED(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3_UNUSED(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr(c) { return c; }
function _Utils_chr_UNUSED(c) { return new String(c); }


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



var _List_Nil = { $: 0 };
var _List_Nil_UNUSED = { $: '[]' };

function _List_Cons(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons_UNUSED(hd, tl) { return { $: '::', a: hd, b: tl }; }


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

var _Debug_log = F2(function(tag, value)
{
	return value;
});

var _Debug_log_UNUSED = F2(function(tag, value)
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

function _Debug_toString(value)
{
	return '<internals>';
}

function _Debug_toString_UNUSED(value)
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


function _Debug_crash(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash_UNUSED(identifier, fact1, fact2, fact3, fact4)
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
	if (region.gP.d2 === region.hC.d2)
	{
		return 'on line ' + region.gP.d2;
	}
	return 'on lines ' + region.gP.d2 + ' through ' + region.hC.d2;
}



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



/**_UNUSED/
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

function _Json_wrap_UNUSED(value) { return { $: 0, a: value }; }
function _Json_unwrap_UNUSED(value) { return value.a; }

function _Json_wrap(value) { return value; }
function _Json_unwrap(value) { return value; }

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
		impl.kk,
		impl.lw,
		impl.lk,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**_UNUSED/, _Json_errorToString(result.a) /**/);
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


function _Platform_export(exports)
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


function _Platform_export_UNUSED(exports)
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

	/**/
	var node = args['node'];
	//*/
	/**_UNUSED/
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
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		? _Json_wrap(
			/**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
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
		gl: func(record.gl),
		gQ: record.gQ,
		gG: record.gG
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
		var message = !tag ? value : tag < 3 ? value.a : value.gl;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.gQ;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.gG) && event.preventDefault(),
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
		impl.kk,
		impl.lw,
		impl.lk,
		function(sendToApp, initialModel) {
			var view = impl.lA;
			/**/
			var domNode = args['node'];
			//*/
			/**_UNUSED/
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
		impl.kk,
		impl.lw,
		impl.lk,
		function(sendToApp, initialModel) {
			var divertHrefToApp = impl.gN && impl.gN(sendToApp)
			var view = impl.lA;
			var title = _VirtualDom_doc.title;
			var bodyNode = _VirtualDom_doc.body;
			var currNode = _VirtualDom_virtualize(bodyNode);
			return _Browser_makeAnimator(initialModel, function(model)
			{
				_VirtualDom_divertHrefToApp = divertHrefToApp;
				var doc = view(model);
				var nextNode = _VirtualDom_node('body')(_List_Nil)(doc.hk);
				var patches = _VirtualDom_diff(currNode, nextNode);
				bodyNode = _VirtualDom_applyPatches(bodyNode, currNode, patches, sendToApp);
				currNode = nextNode;
				_VirtualDom_divertHrefToApp = 0;
				(title !== doc.ds) && (_VirtualDom_doc.title = title = doc.ds);
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
	var onUrlChange = impl.kM;
	var onUrlRequest = impl.kN;
	var key = function() { key.a(onUrlChange(_Browser_getUrl())); };

	return _Browser_document({
		gN: function(sendToApp)
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
							&& curr.iW === next.iW
							&& curr.hQ === next.hQ
							&& curr.iV.a === next.iV.a
						)
							? $elm$browser$Browser$Internal(next)
							: $elm$browser$Browser$External(href)
					));
				}
			});
		},
		kk: function(flags)
		{
			return A3(impl.kk, flags, _Browser_getUrl(), key);
		},
		lA: impl.lA,
		lw: impl.lw,
		lk: impl.lk
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
		? { dS: 'hidden', jP: 'visibilitychange' }
		:
	(typeof _VirtualDom_doc.mozHidden !== 'undefined')
		? { dS: 'mozHidden', jP: 'mozvisibilitychange' }
		:
	(typeof _VirtualDom_doc.msHidden !== 'undefined')
		? { dS: 'msHidden', jP: 'msvisibilitychange' }
		:
	(typeof _VirtualDom_doc.webkitHidden !== 'undefined')
		? { dS: 'webkitHidden', jP: 'webkitvisibilitychange' }
		: { dS: 'hidden', jP: 'visibilitychange' };
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
		dr: _Browser_getScene(),
		dx: {
			L: _Browser_window.pageXOffset,
			ap: _Browser_window.pageYOffset,
			jv: _Browser_doc.documentElement.clientWidth,
			f8: _Browser_doc.documentElement.clientHeight
		}
	};
}

function _Browser_getScene()
{
	var body = _Browser_doc.body;
	var elem = _Browser_doc.documentElement;
	return {
		jv: Math.max(body.scrollWidth, body.offsetWidth, elem.scrollWidth, elem.offsetWidth, elem.clientWidth),
		f8: Math.max(body.scrollHeight, body.offsetHeight, elem.scrollHeight, elem.offsetHeight, elem.clientHeight)
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
			dr: {
				jv: node.scrollWidth,
				f8: node.scrollHeight
			},
			dx: {
				L: node.scrollLeft,
				ap: node.scrollTop,
				jv: node.clientWidth,
				f8: node.clientHeight
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
			dr: _Browser_getScene(),
			dx: {
				L: x,
				ap: y,
				jv: _Browser_doc.documentElement.clientWidth,
				f8: _Browser_doc.documentElement.clientHeight
			},
			fS: {
				L: x + rect.left,
				ap: y + rect.top,
				jv: rect.width,
				f8: rect.height
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



// SEND REQUEST

var _Http_toTask = F3(function(router, toTask, request)
{
	return _Scheduler_binding(function(callback)
	{
		function done(response) {
			callback(toTask(request.hI.a(response)));
		}

		var xhr = new XMLHttpRequest();
		xhr.addEventListener('error', function() { done($elm$http$Http$NetworkError_); });
		xhr.addEventListener('timeout', function() { done($elm$http$Http$Timeout_); });
		xhr.addEventListener('load', function() { done(_Http_toResponse(request.hI.b, xhr)); });
		$elm$core$Maybe$isJust(request.jn) && _Http_track(router, xhr, request.jn.a);

		try {
			xhr.open(request.ik, request.jr, true);
		} catch (e) {
			return done($elm$http$Http$BadUrl_(request.jr));
		}

		_Http_configureRequest(xhr, request);

		request.hk.a && xhr.setRequestHeader('Content-Type', request.hk.a);
		xhr.send(request.hk.b);

		return function() { xhr.c = true; xhr.abort(); };
	});
});


// CONFIGURE

function _Http_configureRequest(xhr, request)
{
	for (var headers = request.hO; headers.b; headers = headers.b) // WHILE_CONS
	{
		xhr.setRequestHeader(headers.a.a, headers.a.b);
	}
	xhr.timeout = request.jf.a || 0;
	xhr.responseType = request.hI.d;
	xhr.withCredentials = request.jC;
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
		jr: xhr.responseURL,
		lg: xhr.status,
		lh: xhr.statusText,
		hO: _Http_parseHeaders(xhr.getAllResponseHeaders())
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
			k8: event.loaded,
			le: event.total
		}))));
	});
	xhr.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Receiving({
			k_: event.loaded,
			le: event.lengthComputable ? $elm$core$Maybe$Just(event.total) : $elm$core$Maybe$Nothing
		}))));
	});
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
var $elm$core$Basics$EQ = 1;
var $elm$core$Basics$GT = 2;
var $elm$core$Basics$LT = 0;
var $elm$core$List$cons = _List_cons;
var $elm$core$Dict$foldr$ = function (func, acc, t) {
	foldr:
	while (true) {
		if (t.$ === -2) {
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
	var dict = _v0;
	return $elm$core$Dict$keys(dict);
};
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr$ = function (func, baseCase, _v0) {
	var tree = _v0.c;
	var tail = _v0.d;
	var helper = F2(
		function (node, acc) {
			if (!node.$) {
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
var $elm$core$Result$Err = function (a) {
	return {$: 1, a: a};
};
var $elm$json$Json$Decode$Failure$ = function (a, b) {
	return {$: 3, a: a, b: b};
};
var $elm$json$Json$Decode$Failure = F2($elm$json$Json$Decode$Failure$);
var $elm$json$Json$Decode$Field$ = function (a, b) {
	return {$: 0, a: a, b: b};
};
var $elm$json$Json$Decode$Field = F2($elm$json$Json$Decode$Field$);
var $elm$json$Json$Decode$Index$ = function (a, b) {
	return {$: 1, a: a, b: b};
};
var $elm$json$Json$Decode$Index = F2($elm$json$Json$Decode$Index$);
var $elm$core$Result$Ok = function (a) {
	return {$: 0, a: a};
};
var $elm$json$Json$Decode$OneOf = function (a) {
	return {$: 2, a: a};
};
var $elm$core$Basics$False = 1;
var $elm$core$Basics$add = _Basics_add;
var $elm$core$Maybe$Just = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$Nothing = {$: 1};
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
			case 0:
				var f = error.a;
				var err = error.b;
				var isSimple = function () {
					var _v1 = $elm$core$String$uncons(f);
					if (_v1.$ === 1) {
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
			case 1:
				var i = error.a;
				var err = error.b;
				var indexName = '[' + ($elm$core$String$fromInt(i) + ']');
				var $temp$error = err,
					$temp$context = A2($elm$core$List$cons, indexName, context);
				error = $temp$error;
				context = $temp$context;
				continue errorToStringHelp;
			case 2:
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
	return {$: 0, a: a, b: b, c: c, d: d};
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
	return {$: 1, a: a};
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
	return {$: 0, a: a};
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
	if (!builder.Z) {
		return $elm$core$Array$Array_elm_builtin$(
			$elm$core$Elm$JsArray$length(builder.af),
			$elm$core$Array$shiftStep,
			$elm$core$Elm$JsArray$empty,
			builder.af);
	} else {
		var treeLen = builder.Z * $elm$core$Array$branchFactor;
		var depth = $elm$core$Basics$floor(
			$elm$core$Basics$logBase$($elm$core$Array$branchFactor, treeLen - 1));
		var correctNodeList = reverseNodeList ? $elm$core$List$reverse(builder.an) : builder.an;
		var tree = $elm$core$Array$treeFromBuilder$(correctNodeList, builder.Z);
		return $elm$core$Array$Array_elm_builtin$(
			$elm$core$Elm$JsArray$length(builder.af) + treeLen,
			$elm$core$Basics$max$(5, depth * $elm$core$Array$shiftStep),
			tree,
			builder.af);
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
				{an: nodeList, Z: (len / $elm$core$Array$branchFactor) | 0, af: tail});
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
var $elm$core$Basics$True = 0;
var $elm$core$Result$isOk = function (result) {
	if (!result.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function (handler) {
	switch (handler.$) {
		case 0:
			return 0;
		case 1:
			return 1;
		case 2:
			return 2;
		default:
			return 3;
	}
};
var $elm$browser$Browser$External = function (a) {
	return {$: 1, a: a};
};
var $elm$browser$Browser$Internal = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Basics$identity = function (x) {
	return x;
};
var $elm$browser$Browser$Dom$NotFound = $elm$core$Basics$identity;
var $elm$url$Url$Http = 0;
var $elm$url$Url$Https = 1;
var $elm$url$Url$Url$ = function (protocol, host, port_, path, query, fragment) {
	return {eX: fragment, hQ: host, iK: path, iV: port_, iW: protocol, fc: query};
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
				if (_v1.$ === 1) {
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
		0,
		$elm$core$String$dropLeft$(7, str)) : (A2($elm$core$String$startsWith, 'https://', str) ? $elm$url$Url$chompAfterProtocol$(
		1,
		$elm$core$String$dropLeft$(8, str)) : $elm$core$Maybe$Nothing);
};
var $elm$core$Basics$never = function (_v0) {
	never:
	while (true) {
		var nvr = _v0;
		var $temp$_v0 = nvr;
		_v0 = $temp$_v0;
		continue never;
	}
};
var $elm$core$Task$Perform = $elm$core$Basics$identity;
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed(0);
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
	var task = _v0;
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
			return 0;
		},
		$elm$core$Task$sequence(
			$elm$core$List$map$(
				$elm$core$Task$spawnCmd(router),
				commands)));
};
var $elm$core$Task$onEffects = F3($elm$core$Task$onEffects$);
var $elm$core$Task$onSelfMsg$ = function (_v0, _v1, _v2) {
	return $elm$core$Task$succeed(0);
};
var $elm$core$Task$onSelfMsg = F3($elm$core$Task$onSelfMsg$);
var $elm$core$Task$cmdMap$ = function (tagger, _v0) {
	var task = _v0;
	return $elm$core$Task$map$(tagger, task);
};
var $elm$core$Task$cmdMap = F2($elm$core$Task$cmdMap$);
_Platform_effectManagers['Task'] = _Platform_createManager($elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap);
var $elm$core$Task$command = _Platform_leaf('Task');
var $elm$core$Task$perform$ = function (toMessage, task) {
	return $elm$core$Task$command(
		$elm$core$Task$map$(toMessage, task));
};
var $elm$core$Task$perform = F2($elm$core$Task$perform$);
var $elm$browser$Browser$element = _Browser_element;
var $author$project$Mario$Dashboard$ControlIdle = {$: 0};
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $author$project$Mario$Dashboard$GotNetwork = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$Network$ = function (schemaVersion, championId, genome) {
	return {dF: championId, f4: genome, be: schemaVersion};
};
var $author$project$Mario$Dashboard$Api$Network = F3($author$project$Mario$Dashboard$Api$Network$);
var $author$project$Mario$Dashboard$Api$Genome$ = function (schemaVersion, nodes, genes) {
	return {ke: genes, iE: nodes, be: schemaVersion};
};
var $author$project$Mario$Dashboard$Api$Genome = F3($author$project$Mario$Dashboard$Api$Genome$);
var $author$project$Mario$Dashboard$Api$Gene$ = function (innovation, from, to, weight, enabled) {
	return {fX: enabled, f1: from, ga: innovation, gY: to, g2: weight};
};
var $author$project$Mario$Dashboard$Api$Gene = F5($author$project$Mario$Dashboard$Api$Gene$);
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom = $elm$json$Json$Decode$map2($elm$core$Basics$apR);
var $elm$json$Json$Decode$andThen = _Json_andThen;
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$json$Json$Decode$at$ = function (fields, decoder) {
	return $elm$core$List$foldr$($elm$json$Json$Decode$field, decoder, fields);
};
var $elm$json$Json$Decode$at = F2($elm$json$Json$Decode$at$);
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
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
		if (!_v0.$) {
			var rawValue = _v0.a;
			var _v1 = A2(
				$elm$json$Json$Decode$decodeValue,
				nullOr(valDecoder),
				rawValue);
			if (!_v1.$) {
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
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$ = function (key, valDecoder, decoder) {
	return A2(
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
		A2($elm$json$Json$Decode$field, key, valDecoder),
		decoder);
};
var $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required = F3($NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$);
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$core$Basics$isInfinite = _Basics_isInfinite;
var $elm$core$Basics$isNaN = _Basics_isNaN;
var $author$project$Mario$Dashboard$Api$safeFloat = function (fallback) {
	return A2(
		$elm$json$Json$Decode$map,
		function (x) {
			return ($elm$core$Basics$isNaN(x) || $elm$core$Basics$isInfinite(x)) ? fallback : x;
		},
		$elm$json$Json$Decode$float);
};
var $author$project$Mario$Dashboard$Api$decodeGene = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'enabled',
	$elm$json$Json$Decode$bool,
	true,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'weight',
		$author$project$Mario$Dashboard$Api$safeFloat(0),
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
			'to',
			$elm$json$Json$Decode$int,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
				'from',
				$elm$json$Json$Decode$int,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'innovation',
					$elm$json$Json$Decode$int,
					0,
					$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Gene))))));
var $author$project$Mario$Dashboard$Api$Node$ = function (id, kind) {
	return {e1: id, gf: kind};
};
var $author$project$Mario$Dashboard$Api$Node = F2($author$project$Mario$Dashboard$Api$Node$);
var $author$project$Mario$Dashboard$Api$UnknownKind = function (a) {
	return {$: 3, a: a};
};
var $author$project$Mario$Dashboard$Api$HiddenNode = {$: 2};
var $author$project$Mario$Dashboard$Api$InputNode = {$: 0};
var $author$project$Mario$Dashboard$Api$OutputNode = {$: 1};
var $author$project$Mario$Dashboard$Api$nodeKindFromString = function (raw) {
	switch (raw) {
		case 'input':
			return $author$project$Mario$Dashboard$Api$InputNode;
		case 'output':
			return $author$project$Mario$Dashboard$Api$OutputNode;
		case 'hidden':
			return $author$project$Mario$Dashboard$Api$HiddenNode;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownKind(other);
	}
};
var $elm$json$Json$Decode$string = _Json_decodeString;
var $author$project$Mario$Dashboard$Api$decodeNode = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'kind',
	A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$nodeKindFromString, $elm$json$Json$Decode$string),
	$author$project$Mario$Dashboard$Api$UnknownKind('unreported'),
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$required$(
		'id',
		$elm$json$Json$Decode$int,
		$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Node)));
var $elm$json$Json$Decode$list = _Json_decodeList;
var $author$project$Mario$Dashboard$Api$decodeGenome = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'genes',
	$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeGene),
	_List_Nil,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'nodes',
		$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeNode),
		_List_Nil,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'schema_version',
			$elm$json$Json$Decode$int,
			1,
			$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Genome))));
var $author$project$Mario$Dashboard$Api$emptyGenome = {ke: _List_Nil, iE: _List_Nil, be: 1};
var $elm$core$Maybe$andThen$ = function (callback, maybeValue) {
	if (!maybeValue.$) {
		var value = maybeValue.a;
		return callback(value);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$Maybe$andThen = F2($elm$core$Maybe$andThen$);
var $elm$json$Json$Decode$nullable = function (decoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$elm$json$Json$Decode$null($elm$core$Maybe$Nothing),
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder)
			]));
};
var $author$project$Mario$Dashboard$Api$namedOrNothing = A2(
	$elm$json$Json$Decode$map,
	$elm$core$Maybe$andThen(
		function (text) {
			return $elm$core$String$isEmpty(text) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(text);
		}),
	$elm$json$Json$Decode$nullable($elm$json$Json$Decode$string));
var $elm$core$Maybe$withDefault$ = function (_default, maybe) {
	if (!maybe.$) {
		var value = maybe.a;
		return value;
	} else {
		return _default;
	}
};
var $elm$core$Maybe$withDefault = F2($elm$core$Maybe$withDefault$);
var $author$project$Mario$Dashboard$Api$decodeNetwork = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'genome',
	A2(
		$elm$json$Json$Decode$map,
		$elm$core$Maybe$withDefault($author$project$Mario$Dashboard$Api$emptyGenome),
		$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeGenome)),
	$author$project$Mario$Dashboard$Api$emptyGenome,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'champion_id',
		$author$project$Mario$Dashboard$Api$namedOrNothing,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'schema_version',
			$elm$json$Json$Decode$int,
			0,
			$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Network))));
var $elm$http$Http$BadStatus_$ = function (a, b) {
	return {$: 3, a: a, b: b};
};
var $elm$http$Http$BadStatus_ = F2($elm$http$Http$BadStatus_$);
var $elm$http$Http$BadUrl_ = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$GoodStatus_$ = function (a, b) {
	return {$: 4, a: a, b: b};
};
var $elm$http$Http$GoodStatus_ = F2($elm$http$Http$GoodStatus_$);
var $elm$http$Http$NetworkError_ = {$: 2};
var $elm$http$Http$Receiving = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$Sending = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$Timeout_ = {$: 1};
var $elm$core$Dict$RBEmpty_elm_builtin = {$: -2};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$core$Maybe$isJust = function (maybe) {
	if (!maybe.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$get$ = function (targetKey, dict) {
	get:
	while (true) {
		if (dict.$ === -2) {
			return $elm$core$Maybe$Nothing;
		} else {
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			var _v1 = A2($elm$core$Basics$compare, targetKey, key);
			switch (_v1) {
				case 0:
					var $temp$dict = left;
					dict = $temp$dict;
					continue get;
				case 1:
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
var $elm$core$Dict$Black = 1;
var $elm$core$Dict$RBNode_elm_builtin$ = function (a, b, c, d, e) {
	return {$: -1, a: a, b: b, c: c, d: d, e: e};
};
var $elm$core$Dict$RBNode_elm_builtin = F5($elm$core$Dict$RBNode_elm_builtin$);
var $elm$core$Dict$Red = 0;
var $elm$core$Dict$balance$ = function (color, key, value, left, right) {
	if ((right.$ === -1) && (!right.a)) {
		var _v1 = right.a;
		var rK = right.b;
		var rV = right.c;
		var rLeft = right.d;
		var rRight = right.e;
		if ((left.$ === -1) && (!left.a)) {
			var _v3 = left.a;
			var lK = left.b;
			var lV = left.c;
			var lLeft = left.d;
			var lRight = left.e;
			return $elm$core$Dict$RBNode_elm_builtin$(
				0,
				key,
				value,
				$elm$core$Dict$RBNode_elm_builtin$(1, lK, lV, lLeft, lRight),
				$elm$core$Dict$RBNode_elm_builtin$(1, rK, rV, rLeft, rRight));
		} else {
			return $elm$core$Dict$RBNode_elm_builtin$(
				color,
				rK,
				rV,
				$elm$core$Dict$RBNode_elm_builtin$(0, key, value, left, rLeft),
				rRight);
		}
	} else {
		if ((((left.$ === -1) && (!left.a)) && (left.d.$ === -1)) && (!left.d.a)) {
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
				0,
				lK,
				lV,
				$elm$core$Dict$RBNode_elm_builtin$(1, llK, llV, llLeft, llRight),
				$elm$core$Dict$RBNode_elm_builtin$(1, key, value, lRight, right));
		} else {
			return $elm$core$Dict$RBNode_elm_builtin$(color, key, value, left, right);
		}
	}
};
var $elm$core$Dict$balance = F5($elm$core$Dict$balance$);
var $elm$core$Dict$insertHelp$ = function (key, value, dict) {
	if (dict.$ === -2) {
		return $elm$core$Dict$RBNode_elm_builtin$(0, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
	} else {
		var nColor = dict.a;
		var nKey = dict.b;
		var nValue = dict.c;
		var nLeft = dict.d;
		var nRight = dict.e;
		var _v1 = A2($elm$core$Basics$compare, key, nKey);
		switch (_v1) {
			case 0:
				return $elm$core$Dict$balance$(
					nColor,
					nKey,
					nValue,
					$elm$core$Dict$insertHelp$(key, value, nLeft),
					nRight);
			case 1:
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
	if ((_v0.$ === -1) && (!_v0.a)) {
		var _v1 = _v0.a;
		var k = _v0.b;
		var v = _v0.c;
		var l = _v0.d;
		var r = _v0.e;
		return $elm$core$Dict$RBNode_elm_builtin$(1, k, v, l, r);
	} else {
		var x = _v0;
		return x;
	}
};
var $elm$core$Dict$insert = F3($elm$core$Dict$insert$);
var $elm$core$Dict$getMin = function (dict) {
	getMin:
	while (true) {
		if ((dict.$ === -1) && (dict.d.$ === -1)) {
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
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.e.d.$ === -1) && (!dict.e.d.a)) {
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
				0,
				rlK,
				rlV,
				$elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$(0, lK, lV, lLeft, lRight),
					rlL),
				$elm$core$Dict$RBNode_elm_builtin$(1, rK, rV, rlR, rRight));
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
			if (clr === 1) {
				return $elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$(0, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$(0, rK, rV, rLeft, rRight));
			} else {
				return $elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$(0, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$(0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$moveRedRight = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.d.d.$ === -1) && (!dict.d.d.a)) {
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
				0,
				lK,
				lV,
				$elm$core$Dict$RBNode_elm_builtin$(1, llK, llV, llLeft, llRight),
				$elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					lRight,
					$elm$core$Dict$RBNode_elm_builtin$(0, rK, rV, rLeft, rRight)));
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
			if (clr === 1) {
				return $elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$(0, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$(0, rK, rV, rLeft, rRight));
			} else {
				return $elm$core$Dict$RBNode_elm_builtin$(
					1,
					k,
					v,
					$elm$core$Dict$RBNode_elm_builtin$(0, lK, lV, lLeft, lRight),
					$elm$core$Dict$RBNode_elm_builtin$(0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT$ = function (targetKey, dict, color, key, value, left, right) {
	if ((left.$ === -1) && (!left.a)) {
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
			$elm$core$Dict$RBNode_elm_builtin$(0, key, value, lRight, right));
	} else {
		_v2$2:
		while (true) {
			if ((right.$ === -1) && (right.a === 1)) {
				if (right.d.$ === -1) {
					if (right.d.a === 1) {
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
	if ((dict.$ === -1) && (dict.d.$ === -1)) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var lColor = left.a;
		var lLeft = left.d;
		var right = dict.e;
		if (lColor === 1) {
			if ((lLeft.$ === -1) && (!lLeft.a)) {
				var _v3 = lLeft.a;
				return $elm$core$Dict$RBNode_elm_builtin$(
					color,
					key,
					value,
					$elm$core$Dict$removeMin(left),
					right);
			} else {
				var _v4 = $elm$core$Dict$moveRedLeft(dict);
				if (_v4.$ === -1) {
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
	if (dict.$ === -2) {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	} else {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var right = dict.e;
		if (_Utils_cmp(targetKey, key) < 0) {
			if ((left.$ === -1) && (left.a === 1)) {
				var _v4 = left.a;
				var lLeft = left.d;
				if ((lLeft.$ === -1) && (!lLeft.a)) {
					var _v6 = lLeft.a;
					return $elm$core$Dict$RBNode_elm_builtin$(
						color,
						key,
						value,
						$elm$core$Dict$removeHelp$(targetKey, left),
						right);
				} else {
					var _v7 = $elm$core$Dict$moveRedLeft(dict);
					if (_v7.$ === -1) {
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
	if (dict.$ === -1) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var right = dict.e;
		if (_Utils_eq(targetKey, key)) {
			var _v1 = $elm$core$Dict$getMin(right);
			if (_v1.$ === -1) {
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
	if ((_v0.$ === -1) && (!_v0.a)) {
		var _v1 = _v0.a;
		var k = _v0.b;
		var v = _v0.c;
		var l = _v0.d;
		var r = _v0.e;
		return $elm$core$Dict$RBNode_elm_builtin$(1, k, v, l, r);
	} else {
		var x = _v0;
		return x;
	}
};
var $elm$core$Dict$remove = F2($elm$core$Dict$remove$);
var $elm$core$Dict$update$ = function (targetKey, alter, dictionary) {
	var _v0 = alter(
		$elm$core$Dict$get$(targetKey, dictionary));
	if (!_v0.$) {
		var value = _v0.a;
		return $elm$core$Dict$insert$(targetKey, value, dictionary);
	} else {
		return $elm$core$Dict$remove$(targetKey, dictionary);
	}
};
var $elm$core$Dict$update = F3($elm$core$Dict$update$);
var $elm$http$Http$emptyBody = _Http_emptyBody;
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
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
	if (!result.$) {
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
	return {$: 4, a: a};
};
var $elm$http$Http$BadStatus = function (a) {
	return {$: 3, a: a};
};
var $elm$http$Http$BadUrl = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$NetworkError = {$: 2};
var $elm$http$Http$Timeout = {$: 1};
var $elm$http$Http$resolve$ = function (toResult, response) {
	switch (response.$) {
		case 0:
			var url = response.a;
			return $elm$core$Result$Err(
				$elm$http$Http$BadUrl(url));
		case 1:
			return $elm$core$Result$Err($elm$http$Http$Timeout);
		case 2:
			return $elm$core$Result$Err($elm$http$Http$NetworkError);
		case 3:
			var metadata = response.a;
			return $elm$core$Result$Err(
				$elm$http$Http$BadStatus(metadata.lg));
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
var $elm$http$Http$Request = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$State$ = function (reqs, subs) {
	return {ff: reqs, ft: subs};
};
var $elm$http$Http$State = F2($elm$http$Http$State$);
var $elm$http$Http$init = $elm$core$Task$succeed(
	$elm$http$Http$State$($elm$core$Dict$empty, _List_Nil));
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$http$Http$updateReqs$ = function (router, cmds, reqs) {
	updateReqs:
	while (true) {
		if (!cmds.b) {
			return $elm$core$Task$succeed(reqs);
		} else {
			var cmd = cmds.a;
			var otherCmds = cmds.b;
			if (!cmd.$) {
				var tracker = cmd.a;
				var _v2 = $elm$core$Dict$get$(tracker, reqs);
				if (_v2.$ === 1) {
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
						var _v4 = req.jn;
						if (_v4.$ === 1) {
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
		$elm$http$Http$updateReqs$(router, cmds, state.ff));
};
var $elm$http$Http$onEffects = F4($elm$http$Http$onEffects$);
var $elm$core$List$maybeCons$ = function (f, mx, xs) {
	var _v0 = f(mx);
	if (!_v0.$) {
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
				state.ft)));
};
var $elm$http$Http$onSelfMsg = F3($elm$http$Http$onSelfMsg$);
var $elm$http$Http$Cancel = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$cmdMap$ = function (func, cmd) {
	if (!cmd.$) {
		var tracker = cmd.a;
		return $elm$http$Http$Cancel(tracker);
	} else {
		var r = cmd.a;
		return $elm$http$Http$Request(
			{
				jC: r.jC,
				hk: r.hk,
				hI: A2(_Http_mapExpect, func, r.hI),
				hO: r.hO,
				ik: r.ik,
				jf: r.jf,
				jn: r.jn,
				jr: r.jr
			});
	}
};
var $elm$http$Http$cmdMap = F2($elm$http$Http$cmdMap$);
var $elm$http$Http$MySub$ = function (a, b) {
	return {$: 0, a: a, b: b};
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
			{jC: false, hk: r.hk, hI: r.hI, hO: r.hO, ik: r.ik, jf: r.jf, jn: r.jn, jr: r.jr}));
};
var $author$project$Mario$Dashboard$requestTimeout = $elm$core$Maybe$Just(10000);
var $author$project$Mario$Dashboard$getJson$ = function (url, toMsg, decoder) {
	return $elm$http$Http$request(
		{
			hk: $elm$http$Http$emptyBody,
			hI: $elm$http$Http$expectJson$(toMsg, decoder),
			hO: _List_Nil,
			ik: 'GET',
			jf: $author$project$Mario$Dashboard$requestTimeout,
			jn: $elm$core$Maybe$Nothing,
			jr: url
		});
};
var $author$project$Mario$Dashboard$getJson = F3($author$project$Mario$Dashboard$getJson$);
var $author$project$Mario$Dashboard$networkUrl = '/api/network';
var $author$project$Mario$Dashboard$fetchNetwork = $author$project$Mario$Dashboard$getJson$($author$project$Mario$Dashboard$networkUrl, $author$project$Mario$Dashboard$GotNetwork, $author$project$Mario$Dashboard$Api$decodeNetwork);
var $author$project$Mario$Dashboard$GotStatus = function (a) {
	return {$: 1, a: a};
};
var $author$project$Mario$Dashboard$Api$Status$ = function (schemaVersion, runId, phase, message, generation, episodes, episodesUnresolved, episodesCombatWins, elapsedSeconds, episodesPerSecond, updatedAt, stale, scoring, board, champion, population, checkpoint, resources, work, phases, benchmark, readiness, history, overall, shipPerformance, sampler, matchups, events) {
	return {hh: benchmark, fH: board, eJ: champion, jQ: checkpoint, j4: elapsedSeconds, c4: episodes, hE: episodesCombatWins, hF: episodesPerSecond, fY: episodesUnresolved, hH: events, f3: generation, c6: history, dd: matchups, gl: message, cd: overall, bz: phase, kT: phases, kV: population, kZ: readiness, gJ: resources, i1: runId, k6: sampler, be: schemaVersion, m: scoring, fn: shipPerformance, jd: stale, fB: updatedAt, jw: work};
};
var $author$project$Mario$Dashboard$Api$Status = function (schemaVersion) {
	return function (runId) {
		return function (phase) {
			return function (message) {
				return function (generation) {
					return function (episodes) {
						return function (episodesUnresolved) {
							return function (episodesCombatWins) {
								return function (elapsedSeconds) {
									return function (episodesPerSecond) {
										return function (updatedAt) {
											return function (stale) {
												return function (scoring) {
													return function (board) {
														return function (champion) {
															return function (population) {
																return function (checkpoint) {
																	return function (resources) {
																		return function (work) {
																			return function (phases) {
																				return function (benchmark) {
																					return function (readiness) {
																						return function (history) {
																							return function (overall) {
																								return function (shipPerformance) {
																									return function (sampler) {
																										return function (matchups) {
																											return function (events) {
																												return $author$project$Mario$Dashboard$Api$Status$(schemaVersion, runId, phase, message, generation, episodes, episodesUnresolved, episodesCombatWins, elapsedSeconds, episodesPerSecond, updatedAt, stale, scoring, board, champion, population, checkpoint, resources, work, phases, benchmark, readiness, history, overall, shipPerformance, sampler, matchups, events);
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
var $author$project$Mario$Dashboard$Api$UnknownPhase = function (a) {
	return {$: 5, a: a};
};
var $author$project$Mario$Dashboard$Api$Benchmark$ = function (at, build, definition, repetitions, fights, bestSeconds, cpuNanosPerDisplayTick, cpuNanosPerLinkActivation, comparableRows) {
	return {he: at, jK: bestSeconds, jM: build, hu: comparableRows, eN: cpuNanosPerDisplayTick, hw: cpuNanosPerLinkActivation, j_: definition, kb: fights, k1: repetitions};
};
var $author$project$Mario$Dashboard$Api$Benchmark = F9($author$project$Mario$Dashboard$Api$Benchmark$);
var $author$project$Mario$Dashboard$Api$finiteFloat = A2(
	$elm$json$Json$Decode$map,
	$elm$core$Maybe$andThen(
		function (x) {
			return ($elm$core$Basics$isNaN(x) || $elm$core$Basics$isInfinite(x)) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(x);
		}),
	$elm$json$Json$Decode$nullable($elm$json$Json$Decode$float));
var $author$project$Mario$Dashboard$Api$decodeBenchmark = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'comparable_rows',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'cpu_nanoseconds_per_link_activation',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'cpu_nanoseconds_per_display_tick',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'best_seconds',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'fights',
					$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'repetitions',
						$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
						$elm$core$Maybe$Nothing,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'definition',
							$author$project$Mario$Dashboard$Api$namedOrNothing,
							$elm$core$Maybe$Nothing,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'build',
								$author$project$Mario$Dashboard$Api$namedOrNothing,
								$elm$core$Maybe$Nothing,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'at',
									$author$project$Mario$Dashboard$Api$namedOrNothing,
									$elm$core$Maybe$Nothing,
									$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Benchmark))))))))));
var $author$project$Mario$Dashboard$Api$Board = function (totalMatchups) {
	return {ji: totalMatchups};
};
var $author$project$Mario$Dashboard$Api$decodeBoard = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'total_matchups',
	$elm$json$Json$Decode$int,
	0,
	$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Board));
var $author$project$Mario$Dashboard$Api$Champion$ = function (id, nodes, connections, hiddenNodes) {
	return {eM: connections, e0: hiddenNodes, e1: id, iE: nodes};
};
var $author$project$Mario$Dashboard$Api$Champion = F4($author$project$Mario$Dashboard$Api$Champion$);
var $author$project$Mario$Dashboard$Api$decodeChampion = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'hidden_nodes',
	$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
	$elm$core$Maybe$Nothing,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'connections',
		$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'nodes',
			$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'id',
				$author$project$Mario$Dashboard$Api$namedOrNothing,
				$elm$core$Maybe$Nothing,
				$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Champion)))));
var $author$project$Mario$Dashboard$Api$Checkpoint$ = function (savedAt, generation, resumable, path) {
	return {f3: generation, iK: path, k2: resumable, k7: savedAt};
};
var $author$project$Mario$Dashboard$Api$Checkpoint = F4($author$project$Mario$Dashboard$Api$Checkpoint$);
var $author$project$Mario$Dashboard$Api$decodeCheckpoint = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'path',
	$elm$json$Json$Decode$string,
	'',
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'resumable',
		$elm$json$Json$Decode$bool,
		false,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'generation',
			$elm$json$Json$Decode$int,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'saved_at',
				$elm$json$Json$Decode$nullable($elm$json$Json$Decode$string),
				$elm$core$Maybe$Nothing,
				$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Checkpoint)))));
var $author$project$Mario$Dashboard$Api$Event$ = function (at, message) {
	return {he: at, gl: message};
};
var $author$project$Mario$Dashboard$Api$Event = F2($author$project$Mario$Dashboard$Api$Event$);
var $author$project$Mario$Dashboard$Api$decodeEvent = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'message',
	$elm$json$Json$Decode$string,
	'',
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'at',
		$elm$json$Json$Decode$string,
		'',
		$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Event)));
var $author$project$Mario$Dashboard$Api$HistoryPoint$ = function (generation, trainingWinRate, validationWinRate, species, nodes, episodes) {
	return {c4: episodes, f3: generation, iE: nodes, jc: species, ls: trainingWinRate, ly: validationWinRate};
};
var $author$project$Mario$Dashboard$Api$HistoryPoint = F6($author$project$Mario$Dashboard$Api$HistoryPoint$);
var $author$project$Mario$Dashboard$Api$decodeHistoryPoint = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'episodes',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'nodes',
		$elm$json$Json$Decode$int,
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'species',
			$elm$json$Json$Decode$int,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'validation_win_rate',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'training_win_rate',
					$author$project$Mario$Dashboard$Api$finiteFloat,
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'generation',
						$elm$json$Json$Decode$int,
						0,
						$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$HistoryPoint)))))));
var $author$project$Mario$Dashboard$Api$Cyborg = {$: 0};
var $author$project$Mario$Dashboard$Api$Matchup$ = function (us, them, opponentType, sampleWeight, trainingGames, trainingWinRate) {
	return {gx: opponentType, fk: sampleWeight, ln: them, lr: trainingGames, ls: trainingWinRate, lx: us};
};
var $author$project$Mario$Dashboard$Api$Matchup = F6($author$project$Mario$Dashboard$Api$Matchup$);
var $author$project$Mario$Dashboard$Api$ModelOpponent = {$: 1};
var $author$project$Mario$Dashboard$Api$UnknownOpponent = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$opponentTypeFromString = function (raw) {
	switch (raw) {
		case 'cyborg':
			return $author$project$Mario$Dashboard$Api$Cyborg;
		case 'model':
			return $author$project$Mario$Dashboard$Api$ModelOpponent;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownOpponent(other);
	}
};
var $author$project$Mario$Dashboard$Api$decodeMatchup = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'training_win_rate',
	$author$project$Mario$Dashboard$Api$finiteFloat,
	$elm$core$Maybe$Nothing,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'training_games',
		$author$project$Mario$Dashboard$Api$safeFloat(0),
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'sample_weight',
			$author$project$Mario$Dashboard$Api$safeFloat(0),
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'opponent_type',
				A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$opponentTypeFromString, $elm$json$Json$Decode$string),
				$author$project$Mario$Dashboard$Api$Cyborg,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'them',
					$elm$json$Json$Decode$string,
					'',
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'us',
						$elm$json$Json$Decode$string,
						'',
						$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Matchup)))))));
var $author$project$Mario$Dashboard$Api$Overall$ = function (scope, target, panel, pairs, round, wins, games, winRate, lowerBound, championId, passed, passedBy, audit, confirm, attempt) {
	return {jF: attempt, jG: audit, dF: championId, jV: confirm, ay: games, e5: lowerBound, kR: pairs, cJ: panel, gB: passed, kS: passedBy, gK: round, gL: scope, aJ: target, g3: winRate, fD: wins};
};
var $author$project$Mario$Dashboard$Api$Overall = function (scope) {
	return function (target) {
		return function (panel) {
			return function (pairs) {
				return function (round) {
					return function (wins) {
						return function (games) {
							return function (winRate) {
								return function (lowerBound) {
									return function (championId) {
										return function (passed) {
											return function (passedBy) {
												return function (audit) {
													return function (confirm) {
														return function (attempt) {
															return $author$project$Mario$Dashboard$Api$Overall$(scope, target, panel, pairs, round, wins, games, winRate, lowerBound, championId, passed, passedBy, audit, confirm, attempt);
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
var $author$project$Mario$Dashboard$Api$RoundResult$ = function (wins, games, winRate, lowerBound, passed) {
	return {ay: games, e5: lowerBound, gB: passed, g3: winRate, fD: wins};
};
var $author$project$Mario$Dashboard$Api$RoundResult = F5($author$project$Mario$Dashboard$Api$RoundResult$);
var $author$project$Mario$Dashboard$Api$decodeRoundResult = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'passed',
	$elm$json$Json$Decode$bool,
	false,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'lower_bound',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'win_rate',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'games',
				$elm$json$Json$Decode$int,
				0,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'wins',
					$elm$json$Json$Decode$int,
					0,
					$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$RoundResult))))));
var $author$project$Mario$Dashboard$Api$emptyRoundResult = {ay: 0, e5: $elm$core$Maybe$Nothing, gB: false, g3: $elm$core$Maybe$Nothing, fD: 0};
var $author$project$Mario$Dashboard$Api$AuditRound = {$: 0};
var $author$project$Mario$Dashboard$Api$ConfirmRound = {$: 1};
var $author$project$Mario$Dashboard$Api$UnknownRound = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$overallRoundFromString = function (raw) {
	switch (raw) {
		case 'audit':
			return $author$project$Mario$Dashboard$Api$AuditRound;
		case 'confirm':
			return $author$project$Mario$Dashboard$Api$ConfirmRound;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownRound(other);
	}
};
var $author$project$Mario$Dashboard$Api$decodeOverall = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'attempt',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'confirm',
		$author$project$Mario$Dashboard$Api$decodeRoundResult,
		$author$project$Mario$Dashboard$Api$emptyRoundResult,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'audit',
			$author$project$Mario$Dashboard$Api$decodeRoundResult,
			$author$project$Mario$Dashboard$Api$emptyRoundResult,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'passed_by',
				$author$project$Mario$Dashboard$Api$namedOrNothing,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'passed',
					$elm$json$Json$Decode$bool,
					false,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'champion_id',
						$author$project$Mario$Dashboard$Api$namedOrNothing,
						$elm$core$Maybe$Nothing,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'lower_bound',
							$author$project$Mario$Dashboard$Api$finiteFloat,
							$elm$core$Maybe$Nothing,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'win_rate',
								$author$project$Mario$Dashboard$Api$finiteFloat,
								$elm$core$Maybe$Nothing,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'games',
									$elm$json$Json$Decode$int,
									0,
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'wins',
										$elm$json$Json$Decode$int,
										0,
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'round',
											$elm$json$Json$Decode$nullable(
												A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$overallRoundFromString, $elm$json$Json$Decode$string)),
											$elm$core$Maybe$Nothing,
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
												'pairs',
												$elm$json$Json$Decode$int,
												0,
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
													'panel',
													$elm$json$Json$Decode$int,
													0,
													$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
														'target',
														$author$project$Mario$Dashboard$Api$safeFloat(0.8),
														0.8,
														$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
															'scope',
															$elm$json$Json$Decode$string,
															'',
															$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Overall))))))))))))))));
var $author$project$Mario$Dashboard$Api$PhaseSplit$ = function (sessionCpuSeconds, sessionWallSeconds, threadsBusy, accountedSeconds, accountedShareOfCpu, unaccountedSeconds, unaccountedShareOfCpu, buckets) {
	return {jz: accountedSeconds, jA: accountedShareOfCpu, jL: buckets, k9: sessionCpuSeconds, la: sessionWallSeconds, lo: threadsBusy, lu: unaccountedSeconds, lv: unaccountedShareOfCpu};
};
var $author$project$Mario$Dashboard$Api$PhaseSplit = F8($author$project$Mario$Dashboard$Api$PhaseSplit$);
var $author$project$Mario$Dashboard$Api$Bucket$ = function (name, seconds, share) {
	return {kB: name, i2: seconds, lb: share};
};
var $author$project$Mario$Dashboard$Api$Bucket = F3($author$project$Mario$Dashboard$Api$Bucket$);
var $author$project$Mario$Dashboard$Api$decodeBucket = function (name) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2(
				$elm$json$Json$Decode$field,
				name,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'share',
					$author$project$Mario$Dashboard$Api$finiteFloat,
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'seconds',
						$author$project$Mario$Dashboard$Api$safeFloat(0),
						0,
						$elm$json$Json$Decode$succeed(
							$author$project$Mario$Dashboard$Api$Bucket(name))))),
				$elm$json$Json$Decode$succeed(
				{kB: name, i2: 0, lb: $elm$core$Maybe$Nothing})
			]));
};
var $author$project$Mario$Dashboard$Api$phaseBucketNames = _List_fromArray(
	['simulate', 'think', 'encode', 'compile', 'evolve', 'checkpoint', 'serve']);
var $author$project$Mario$Dashboard$Api$decodePhaseSplit = A2(
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$custom,
	$elm$core$List$foldr$(
		$elm$json$Json$Decode$map2($elm$core$List$cons),
		$elm$json$Json$Decode$succeed(_List_Nil),
		$elm$core$List$map$($author$project$Mario$Dashboard$Api$decodeBucket, $author$project$Mario$Dashboard$Api$phaseBucketNames)),
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'unaccounted_share_of_cpu',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'unaccounted_seconds',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'accounted_share_of_cpu',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'accounted_seconds',
					$author$project$Mario$Dashboard$Api$safeFloat(0),
					0,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'threads_busy',
						$author$project$Mario$Dashboard$Api$finiteFloat,
						$elm$core$Maybe$Nothing,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'session_wall_seconds',
							$author$project$Mario$Dashboard$Api$safeFloat(0),
							0,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'session_cpu_seconds',
								$author$project$Mario$Dashboard$Api$finiteFloat,
								$elm$core$Maybe$Nothing,
								$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$PhaseSplit)))))))));
var $author$project$Mario$Dashboard$Api$Population$ = function (size, species, meanNodes, meanConnections) {
	return {kt: meanConnections, ku: meanNodes, le: size, jc: species};
};
var $author$project$Mario$Dashboard$Api$Population = F4($author$project$Mario$Dashboard$Api$Population$);
var $author$project$Mario$Dashboard$Api$decodePopulation = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'mean_connections',
	$author$project$Mario$Dashboard$Api$safeFloat(0),
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'mean_nodes',
		$author$project$Mario$Dashboard$Api$safeFloat(0),
		0,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'species',
			$elm$json$Json$Decode$int,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'size',
				$elm$json$Json$Decode$int,
				0,
				$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Population)))));
var $author$project$Mario$Dashboard$Api$Readiness$ = function (threshold, games, lastRate, period) {
	return {ay: games, h0: lastRate, iL: period, je: threshold};
};
var $author$project$Mario$Dashboard$Api$Readiness = F4($author$project$Mario$Dashboard$Api$Readiness$);
var $author$project$Mario$Dashboard$Api$decodeReadiness = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'period',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'last_rate',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'games',
			$elm$json$Json$Decode$int,
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'threshold',
				$author$project$Mario$Dashboard$Api$safeFloat(0),
				0,
				$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Readiness)))));
var $author$project$Mario$Dashboard$Api$Resources$ = function (workers, dutyCycle, measuredDuty, computeSeconds, episodeTicks, nice) {
	return {jU: computeSeconds, eS: dutyCycle, eT: episodeTicks, e6: measuredDuty, kC: nice, fE: workers};
};
var $author$project$Mario$Dashboard$Api$Resources = F6($author$project$Mario$Dashboard$Api$Resources$);
var $author$project$Mario$Dashboard$Api$decodeResources = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'nice',
	$elm$json$Json$Decode$int,
	0,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'episode_ticks',
		$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'compute_seconds',
			$author$project$Mario$Dashboard$Api$safeFloat(0),
			0,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'measured_duty',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'duty_cycle',
					$author$project$Mario$Dashboard$Api$safeFloat(0),
					0,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'workers',
						$elm$json$Json$Decode$int,
						0,
						$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Resources)))))));
var $author$project$Mario$Dashboard$Api$Sampler$ = function (panel, balancedShare, cursor, tour) {
	return {jJ: balancedShare, jY: cursor, cJ: panel, lq: tour};
};
var $author$project$Mario$Dashboard$Api$Sampler = F4($author$project$Mario$Dashboard$Api$Sampler$);
var $author$project$Mario$Dashboard$Api$decodeSampler = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'tour',
	$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
	$elm$core$Maybe$Nothing,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'cursor',
		$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'coverage',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'panel',
				$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
				$elm$core$Maybe$Nothing,
				$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Sampler)))));
var $author$project$Mario$Dashboard$Api$CombatWins = {$: 0};
var $author$project$Mario$Dashboard$Api$Combat = {$: 0};
var $author$project$Mario$Dashboard$Api$CrewRatio = function (a) {
	return {$: 1, a: a};
};
var $author$project$Mario$Dashboard$Api$UnknownFitness = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$fitnessFrom$ = function (raw, zeroOpponent, mutualZero) {
	switch (raw) {
		case 'combat':
			return $author$project$Mario$Dashboard$Api$Combat;
		case 'crew-ratio':
			return $author$project$Mario$Dashboard$Api$CrewRatio(
				{gm: mutualZero, hb: zeroOpponent});
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownFitness(other);
	}
};
var $author$project$Mario$Dashboard$Api$fitnessFrom = F3($author$project$Mario$Dashboard$Api$fitnessFrom$);
var $author$project$Mario$Dashboard$Api$CrewLead = {$: 1};
var $author$project$Mario$Dashboard$Api$UnknownGate = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$gateFrom = function (raw) {
	switch (raw) {
		case 'combat-wins':
			return $author$project$Mario$Dashboard$Api$CombatWins;
		case 'crew-lead':
			return $author$project$Mario$Dashboard$Api$CrewLead;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownGate(other);
	}
};
var $author$project$Mario$Dashboard$Api$PenaltyOf = function (a) {
	return {$: 1, a: a};
};
var $author$project$Mario$Dashboard$Api$PenaltyOff = {$: 0};
var $author$project$Mario$Dashboard$Api$noDamagePenaltyFrom = function (reported) {
	if (!reported.$) {
		var magnitude = reported.a;
		return (magnitude > 0) ? $author$project$Mario$Dashboard$Api$PenaltyOf(magnitude) : $author$project$Mario$Dashboard$Api$PenaltyOff;
	} else {
		return $author$project$Mario$Dashboard$Api$PenaltyOff;
	}
};
var $author$project$Mario$Dashboard$Api$decodeScoring = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'no_damage_penalty',
	$author$project$Mario$Dashboard$Api$finiteFloat,
	$elm$core$Maybe$Nothing,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'gate',
		A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$gateFrom, $elm$json$Json$Decode$string),
		$author$project$Mario$Dashboard$Api$CombatWins,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'speed_bonus',
			$elm$json$Json$Decode$nullable($elm$json$Json$Decode$bool),
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'mutual_zero',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'zero_opponent',
					$author$project$Mario$Dashboard$Api$finiteFloat,
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'fitness',
						$elm$json$Json$Decode$string,
						'',
						$elm$json$Json$Decode$succeed(
							F6(
								function (raw, zeroOpponent, mutualZero, speedBonus, gate, penalty) {
									return {
										kc: $author$project$Mario$Dashboard$Api$fitnessFrom$(raw, zeroOpponent, mutualZero),
										eZ: gate,
										kD: $author$project$Mario$Dashboard$Api$noDamagePenaltyFrom(penalty),
										fp: speedBonus
									};
								}))))))));
var $author$project$Mario$Dashboard$Api$ShipPerformance$ = function (side, ship, wins, games, winRate, lowerBound, source) {
	return {ay: games, e5: lowerBound, lc: ship, ld: side, ja: source, g3: winRate, fD: wins};
};
var $author$project$Mario$Dashboard$Api$ShipPerformance = F7($author$project$Mario$Dashboard$Api$ShipPerformance$);
var $author$project$Mario$Dashboard$Api$UnknownSeat = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Api$UnknownSource = function (a) {
	return {$: 3, a: a};
};
var $author$project$Mario$Dashboard$Api$FromAudit = {$: 0};
var $author$project$Mario$Dashboard$Api$FromConfirm = {$: 1};
var $author$project$Mario$Dashboard$Api$FromReadiness = {$: 2};
var $author$project$Mario$Dashboard$Api$evidenceSourceFromString = function (raw) {
	switch (raw) {
		case 'audit':
			return $author$project$Mario$Dashboard$Api$FromAudit;
		case 'confirm':
			return $author$project$Mario$Dashboard$Api$FromConfirm;
		case 'ready':
			return $author$project$Mario$Dashboard$Api$FromReadiness;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownSource(other);
	}
};
var $author$project$Mario$Dashboard$Api$OpponentSeat = {$: 1};
var $author$project$Mario$Dashboard$Api$OurSeat = {$: 0};
var $author$project$Mario$Dashboard$Api$seatFromString = function (raw) {
	switch (raw) {
		case 'ours':
			return $author$project$Mario$Dashboard$Api$OurSeat;
		case 'opponent':
			return $author$project$Mario$Dashboard$Api$OpponentSeat;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownSeat(other);
	}
};
var $author$project$Mario$Dashboard$Api$decodeShipPerformance = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'source',
	A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$evidenceSourceFromString, $elm$json$Json$Decode$string),
	$author$project$Mario$Dashboard$Api$UnknownSource('unreported'),
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'lower_bound',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'win_rate',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'games',
				$elm$json$Json$Decode$int,
				0,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'wins',
					$elm$json$Json$Decode$int,
					0,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'ship',
						$elm$json$Json$Decode$string,
						'',
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'side',
							A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$seatFromString, $elm$json$Json$Decode$string),
							$author$project$Mario$Dashboard$Api$UnknownSeat('unreported'),
							$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$ShipPerformance))))))));
var $author$project$Mario$Dashboard$Api$Work$ = function (episodes, displayTicks, decisions, nodeActivations, linkActivations, elementScans, elementsVisited, networksCompiled, cpuNanosPerDisplayTick, cpuNanosPerLinkActivation, displayTicksPerEpisode, linkActivationsPerDecision, elementsPerScan) {
	return {eN: cpuNanosPerDisplayTick, hw: cpuNanosPerLinkActivation, fM: decisions, j1: displayTicks, j2: displayTicksPerEpisode, fT: elementScans, fU: elementsPerScan, fV: elementsVisited, c4: episodes, ko: linkActivations, gg: linkActivationsPerDecision, gp: networksCompiled, gq: nodeActivations};
};
var $author$project$Mario$Dashboard$Api$Work = function (episodes) {
	return function (displayTicks) {
		return function (decisions) {
			return function (nodeActivations) {
				return function (linkActivations) {
					return function (elementScans) {
						return function (elementsVisited) {
							return function (networksCompiled) {
								return function (cpuNanosPerDisplayTick) {
									return function (cpuNanosPerLinkActivation) {
										return function (displayTicksPerEpisode) {
											return function (linkActivationsPerDecision) {
												return function (elementsPerScan) {
													return $author$project$Mario$Dashboard$Api$Work$(episodes, displayTicks, decisions, nodeActivations, linkActivations, elementScans, elementsVisited, networksCompiled, cpuNanosPerDisplayTick, cpuNanosPerLinkActivation, displayTicksPerEpisode, linkActivationsPerDecision, elementsPerScan);
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
var $author$project$Mario$Dashboard$Api$decodeWork = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'elements_per_scan',
	$author$project$Mario$Dashboard$Api$finiteFloat,
	$elm$core$Maybe$Nothing,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'link_activations_per_decision',
		$author$project$Mario$Dashboard$Api$finiteFloat,
		$elm$core$Maybe$Nothing,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'display_ticks_per_episode',
			$author$project$Mario$Dashboard$Api$finiteFloat,
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'cpu_nanoseconds_per_link_activation',
				$author$project$Mario$Dashboard$Api$finiteFloat,
				$elm$core$Maybe$Nothing,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'cpu_nanoseconds_per_display_tick',
					$author$project$Mario$Dashboard$Api$finiteFloat,
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'networks_compiled',
						$elm$json$Json$Decode$int,
						0,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'elements_visited',
							$elm$json$Json$Decode$int,
							0,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'element_scans',
								$elm$json$Json$Decode$int,
								0,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'link_activations',
									$elm$json$Json$Decode$int,
									0,
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'node_activations',
										$elm$json$Json$Decode$int,
										0,
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'decisions',
											$elm$json$Json$Decode$int,
											0,
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
												'display_ticks',
												$elm$json$Json$Decode$int,
												0,
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
													'episodes',
													$elm$json$Json$Decode$int,
													0,
													$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Work))))))))))))));
var $author$project$Mario$Dashboard$Api$emptyBoard = {ji: 0};
var $author$project$Mario$Dashboard$Api$emptyChampion = {eM: $elm$core$Maybe$Nothing, e0: $elm$core$Maybe$Nothing, e1: $elm$core$Maybe$Nothing, iE: $elm$core$Maybe$Nothing};
var $author$project$Mario$Dashboard$Api$emptyCheckpoint = {f3: 0, iK: '', k2: false, k7: $elm$core$Maybe$Nothing};
var $author$project$Mario$Dashboard$Api$emptyPopulation = {kt: 0, ku: 0, le: 0, jc: 0};
var $author$project$Mario$Dashboard$Api$emptyReadiness = {ay: 0, h0: $elm$core$Maybe$Nothing, iL: 0, je: 0};
var $author$project$Mario$Dashboard$Api$emptyResources = {jU: 0, eS: 0, eT: $elm$core$Maybe$Nothing, e6: $elm$core$Maybe$Nothing, kC: 0, fE: 0};
var $author$project$Mario$Dashboard$Api$Auditing = {$: 2};
var $author$project$Mario$Dashboard$Api$Initializing = {$: 0};
var $author$project$Mario$Dashboard$Api$Paused = {$: 3};
var $author$project$Mario$Dashboard$Api$Stopped = {$: 4};
var $author$project$Mario$Dashboard$Api$Training = {$: 1};
var $author$project$Mario$Dashboard$Api$phaseFromString = function (raw) {
	switch (raw) {
		case 'initializing':
			return $author$project$Mario$Dashboard$Api$Initializing;
		case 'training':
			return $author$project$Mario$Dashboard$Api$Training;
		case 'auditing':
			return $author$project$Mario$Dashboard$Api$Auditing;
		case 'paused':
			return $author$project$Mario$Dashboard$Api$Paused;
		case 'stopped':
			return $author$project$Mario$Dashboard$Api$Stopped;
		default:
			var other = raw;
			return $author$project$Mario$Dashboard$Api$UnknownPhase(other);
	}
};
var $author$project$Mario$Dashboard$Api$decodeStatus = $NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
	'events',
	$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeEvent),
	_List_Nil,
	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
		'matchups',
		$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeMatchup),
		_List_Nil,
		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
			'sampler',
			$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeSampler),
			$elm$core$Maybe$Nothing,
			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
				'ship_performance',
				$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeShipPerformance),
				_List_Nil,
				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
					'overall',
					$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeOverall),
					$elm$core$Maybe$Nothing,
					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
						'history',
						$elm$json$Json$Decode$list($author$project$Mario$Dashboard$Api$decodeHistoryPoint),
						_List_Nil,
						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
							'readiness',
							$author$project$Mario$Dashboard$Api$decodeReadiness,
							$author$project$Mario$Dashboard$Api$emptyReadiness,
							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
								'benchmark',
								$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeBenchmark),
								$elm$core$Maybe$Nothing,
								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
									'phases',
									$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodePhaseSplit),
									$elm$core$Maybe$Nothing,
									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
										'work',
										$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeWork),
										$elm$core$Maybe$Nothing,
										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
											'resources',
											$author$project$Mario$Dashboard$Api$decodeResources,
											$author$project$Mario$Dashboard$Api$emptyResources,
											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
												'checkpoint',
												$author$project$Mario$Dashboard$Api$decodeCheckpoint,
												$author$project$Mario$Dashboard$Api$emptyCheckpoint,
												$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
													'population',
													$author$project$Mario$Dashboard$Api$decodePopulation,
													$author$project$Mario$Dashboard$Api$emptyPopulation,
													$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
														'champion',
														$author$project$Mario$Dashboard$Api$decodeChampion,
														$author$project$Mario$Dashboard$Api$emptyChampion,
														$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
															'board',
															$author$project$Mario$Dashboard$Api$decodeBoard,
															$author$project$Mario$Dashboard$Api$emptyBoard,
															$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																'scoring',
																$elm$json$Json$Decode$nullable($author$project$Mario$Dashboard$Api$decodeScoring),
																$elm$core$Maybe$Nothing,
																$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																	'stale',
																	$elm$json$Json$Decode$bool,
																	false,
																	$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																		'updated_at',
																		$elm$json$Json$Decode$string,
																		'',
																		$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																			'episodes_per_second',
																			$author$project$Mario$Dashboard$Api$safeFloat(0),
																			0,
																			$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																				'elapsed_seconds',
																				$author$project$Mario$Dashboard$Api$safeFloat(0),
																				0,
																				$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																					'episodes_combat_wins',
																					$elm$json$Json$Decode$nullable($elm$json$Json$Decode$int),
																					$elm$core$Maybe$Nothing,
																					$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																						'episodes_unresolved',
																						$elm$json$Json$Decode$int,
																						0,
																						$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																							'episodes',
																							$elm$json$Json$Decode$int,
																							0,
																							$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																								'generation',
																								$elm$json$Json$Decode$int,
																								0,
																								$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																									'message',
																									$elm$json$Json$Decode$string,
																									'',
																									$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																										'phase',
																										A2($elm$json$Json$Decode$map, $author$project$Mario$Dashboard$Api$phaseFromString, $elm$json$Json$Decode$string),
																										$author$project$Mario$Dashboard$Api$UnknownPhase('unreported'),
																										$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																											'run_id',
																											$elm$json$Json$Decode$string,
																											'',
																											$NoRedInk$elm_json_decode_pipeline$Json$Decode$Pipeline$optional$(
																												'schema_version',
																												$elm$json$Json$Decode$int,
																												0,
																												$elm$json$Json$Decode$succeed($author$project$Mario$Dashboard$Api$Status)))))))))))))))))))))))))))));
var $author$project$Mario$Dashboard$statusUrl = '/api/status';
var $author$project$Mario$Dashboard$fetchStatus = $author$project$Mario$Dashboard$getJson$($author$project$Mario$Dashboard$statusUrl, $author$project$Mario$Dashboard$GotStatus, $author$project$Mario$Dashboard$Api$decodeStatus);
var $elm$time$Time$Posix = $elm$core$Basics$identity;
var $elm$time$Time$millisToPosix = $elm$core$Basics$identity;
var $author$project$Mario$Dashboard$init = function (_v0) {
	return _Utils_Tuple2(
		{
			aV: $author$project$Mario$Dashboard$ControlIdle,
			b7: 0,
			cw: $elm$core$Maybe$Nothing,
			aX: true,
			cE: $elm$core$Maybe$Nothing,
			cF: $elm$core$Maybe$Nothing,
			df: $elm$core$Maybe$Nothing,
			bw: true,
			cH: $elm$core$Maybe$Nothing,
			cI: $elm$core$Maybe$Nothing,
			dj: $elm$time$Time$millisToPosix(0),
			cL: $elm$core$Maybe$Nothing,
			cM: false,
			cO: $elm$core$Maybe$Nothing,
			aI: $elm$core$Maybe$Nothing,
			bi: 0,
			bj: $elm$core$Maybe$Nothing,
			a1: $elm$core$Maybe$Nothing,
			bC: $elm$core$Maybe$Nothing,
			cW: true,
			cX: $elm$core$Maybe$Nothing
		},
		$elm$core$Platform$Cmd$batch(
			_List_fromArray(
				[$author$project$Mario$Dashboard$fetchStatus, $author$project$Mario$Dashboard$fetchNetwork])));
};
var $author$project$Mario$Dashboard$GlobalKey = function (a) {
	return {$: 4, a: a};
};
var $author$project$Mario$Dashboard$Tick = function (a) {
	return {$: 0, a: a};
};
var $author$project$Mario$Dashboard$VisibilityChanged = function (a) {
	return {$: 3, a: a};
};
var $elm$core$Platform$Sub$batch = _Platform_batch;
var $elm$time$Time$Every$ = function (a, b) {
	return {$: 0, a: a, b: b};
};
var $elm$time$Time$Every = F2($elm$time$Time$Every$);
var $elm$time$Time$State$ = function (taggers, processes) {
	return {fb: processes, fu: taggers};
};
var $elm$time$Time$State = F2($elm$time$Time$State$);
var $elm$time$Time$init = $elm$core$Task$succeed(
	$elm$time$Time$State$($elm$core$Dict$empty, $elm$core$Dict$empty));
var $elm$time$Time$addMySub$ = function (_v0, state) {
	var interval = _v0.a;
	var tagger = _v0.b;
	var _v1 = $elm$core$Dict$get$(interval, state);
	if (_v1.$ === 1) {
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
var $elm$core$Dict$foldl$ = function (func, acc, dict) {
	foldl:
	while (true) {
		if (dict.$ === -2) {
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
var $elm$time$Time$Name = function (a) {
	return {$: 0, a: a};
};
var $elm$time$Time$Offset = function (a) {
	return {$: 1, a: a};
};
var $elm$time$Time$Zone$ = function (a, b) {
	return {$: 0, a: a, b: b};
};
var $elm$time$Time$Zone = F2($elm$time$Time$Zone$);
var $elm$time$Time$customZone = $elm$time$Time$Zone;
var $elm$time$Time$setInterval = _Time_setInterval;
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
	var processes = _v0.fb;
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
			$elm$core$Task$succeed(0)));
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
var $elm$time$Time$now = _Time_now($elm$time$Time$millisToPosix);
var $elm$time$Time$onSelfMsg$ = function (router, interval, state) {
	var _v0 = $elm$core$Dict$get$(interval, state.fu);
	if (_v0.$ === 1) {
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
var $author$project$Mario$Dashboard$hiddenPollMillis = 30000;
var $elm$browser$Browser$Events$Document = 0;
var $elm$browser$Browser$Events$MySub$ = function (a, b, c) {
	return {$: 0, a: a, b: b, c: c};
};
var $elm$browser$Browser$Events$MySub = F3($elm$browser$Browser$Events$MySub$);
var $elm$browser$Browser$Events$State$ = function (subs, pids) {
	return {e9: pids, ft: subs};
};
var $elm$browser$Browser$Events$State = F2($elm$browser$Browser$Events$State$);
var $elm$browser$Browser$Events$init = $elm$core$Task$succeed(
	$elm$browser$Browser$Events$State$(_List_Nil, $elm$core$Dict$empty));
var $elm$browser$Browser$Events$nodeToKey = function (node) {
	if (!node) {
		return 'd_';
	} else {
		return 'w_';
	}
};
var $elm$browser$Browser$Events$addKey = function (sub) {
	var node = sub.a;
	var name = sub.b;
	return _Utils_Tuple2(
		_Utils_ap(
			$elm$browser$Browser$Events$nodeToKey(node),
			name),
		sub);
};
var $elm$core$Dict$fromList = function (assocs) {
	return $elm$core$List$foldl$(
		F2(
			function (_v0, dict) {
				var key = _v0.a;
				var value = _v0.b;
				return $elm$core$Dict$insert$(key, value, dict);
			}),
		$elm$core$Dict$empty,
		assocs);
};
var $elm$browser$Browser$Events$Event$ = function (key, event) {
	return {hG: event, e2: key};
};
var $elm$browser$Browser$Events$Event = F2($elm$browser$Browser$Events$Event$);
var $elm$browser$Browser$Events$spawn$ = function (router, key, _v0) {
	var node = _v0.a;
	var name = _v0.b;
	var actualNode = function () {
		if (!node) {
			return _Browser_doc;
		} else {
			return _Browser_window;
		}
	}();
	return $elm$core$Task$map$(
		function (value) {
			return _Utils_Tuple2(key, value);
		},
		A3(
			_Browser_on,
			actualNode,
			name,
			function (event) {
				return A2(
					$elm$core$Platform$sendToSelf,
					router,
					$elm$browser$Browser$Events$Event$(key, event));
			}));
};
var $elm$browser$Browser$Events$spawn = F3($elm$browser$Browser$Events$spawn$);
var $elm$core$Dict$union$ = function (t1, t2) {
	return $elm$core$Dict$foldl$($elm$core$Dict$insert, t2, t1);
};
var $elm$core$Dict$union = F2($elm$core$Dict$union$);
var $elm$browser$Browser$Events$onEffects$ = function (router, subs, state) {
	var stepRight = F3(
		function (key, sub, _v6) {
			var deads = _v6.a;
			var lives = _v6.b;
			var news = _v6.c;
			return _Utils_Tuple3(
				deads,
				lives,
				A2(
					$elm$core$List$cons,
					$elm$browser$Browser$Events$spawn$(router, key, sub),
					news));
		});
	var stepLeft = F3(
		function (_v4, pid, _v5) {
			var deads = _v5.a;
			var lives = _v5.b;
			var news = _v5.c;
			return _Utils_Tuple3(
				A2($elm$core$List$cons, pid, deads),
				lives,
				news);
		});
	var stepBoth = F4(
		function (key, pid, _v2, _v3) {
			var deads = _v3.a;
			var lives = _v3.b;
			var news = _v3.c;
			return _Utils_Tuple3(
				deads,
				$elm$core$Dict$insert$(key, pid, lives),
				news);
		});
	var newSubs = $elm$core$List$map$($elm$browser$Browser$Events$addKey, subs);
	var _v0 = $elm$core$Dict$merge$(
		stepLeft,
		stepBoth,
		stepRight,
		state.e9,
		$elm$core$Dict$fromList(newSubs),
		_Utils_Tuple3(_List_Nil, $elm$core$Dict$empty, _List_Nil));
	var deadPids = _v0.a;
	var livePids = _v0.b;
	var makeNewPids = _v0.c;
	return A2(
		$elm$core$Task$andThen,
		function (pids) {
			return $elm$core$Task$succeed(
				$elm$browser$Browser$Events$State$(
					newSubs,
					$elm$core$Dict$union$(
						livePids,
						$elm$core$Dict$fromList(pids))));
		},
		A2(
			$elm$core$Task$andThen,
			function (_v1) {
				return $elm$core$Task$sequence(makeNewPids);
			},
			$elm$core$Task$sequence(
				$elm$core$List$map$($elm$core$Process$kill, deadPids))));
};
var $elm$browser$Browser$Events$onEffects = F3($elm$browser$Browser$Events$onEffects$);
var $elm$browser$Browser$Events$onSelfMsg$ = function (router, _v0, state) {
	var event = _v0.hG;
	var key = _v0.e2;
	var toMessage = function (_v2) {
		var subKey = _v2.a;
		var _v3 = _v2.b;
		var node = _v3.a;
		var name = _v3.b;
		var decoder = _v3.c;
		return _Utils_eq(subKey, key) ? A2(_Browser_decodeEvent, decoder, event) : $elm$core$Maybe$Nothing;
	};
	var messages = $elm$core$List$filterMap$(toMessage, state.ft);
	return A2(
		$elm$core$Task$andThen,
		function (_v1) {
			return $elm$core$Task$succeed(state);
		},
		$elm$core$Task$sequence(
			$elm$core$List$map$(
				$elm$core$Platform$sendToApp(router),
				messages)));
};
var $elm$browser$Browser$Events$onSelfMsg = F3($elm$browser$Browser$Events$onSelfMsg$);
var $elm$browser$Browser$Events$subMap$ = function (func, _v0) {
	var node = _v0.a;
	var name = _v0.b;
	var decoder = _v0.c;
	return $elm$browser$Browser$Events$MySub$(
		node,
		name,
		A2($elm$json$Json$Decode$map, func, decoder));
};
var $elm$browser$Browser$Events$subMap = F2($elm$browser$Browser$Events$subMap$);
_Platform_effectManagers['Browser.Events'] = _Platform_createManager($elm$browser$Browser$Events$init, $elm$browser$Browser$Events$onEffects, $elm$browser$Browser$Events$onSelfMsg, 0, $elm$browser$Browser$Events$subMap);
var $elm$browser$Browser$Events$subscription = _Platform_leaf('Browser.Events');
var $elm$browser$Browser$Events$on$ = function (node, name, decoder) {
	return $elm$browser$Browser$Events$subscription(
		$elm$browser$Browser$Events$MySub$(node, name, decoder));
};
var $elm$browser$Browser$Events$on = F3($elm$browser$Browser$Events$on$);
var $elm$browser$Browser$Events$onKeyDown = A2($elm$browser$Browser$Events$on, 0, 'keydown');
var $elm$browser$Browser$Events$Hidden = 1;
var $elm$browser$Browser$Events$Visible = 0;
var $elm$browser$Browser$Events$withHidden$ = function (func, isHidden) {
	return func(
		isHidden ? 1 : 0);
};
var $elm$browser$Browser$Events$withHidden = F2($elm$browser$Browser$Events$withHidden$);
var $elm$browser$Browser$Events$onVisibilityChange = function (func) {
	var info = _Browser_visibilityInfo(0);
	return $elm$browser$Browser$Events$on$(
		0,
		info.jP,
		A2(
			$elm$json$Json$Decode$map,
			$elm$browser$Browser$Events$withHidden(func),
			A2(
				$elm$json$Json$Decode$field,
				'target',
				A2($elm$json$Json$Decode$field, info.dS, $elm$json$Json$Decode$bool))));
};
var $author$project$Mario$Dashboard$pollMillis = 2000;
var $author$project$Mario$Dashboard$subscriptions = function (model) {
	return $elm$core$Platform$Sub$batch(
		_List_fromArray(
			[
				$elm$time$Time$every$(
				model.cW ? $author$project$Mario$Dashboard$pollMillis : $author$project$Mario$Dashboard$hiddenPollMillis,
				$author$project$Mario$Dashboard$Tick),
				$elm$browser$Browser$Events$onVisibilityChange($author$project$Mario$Dashboard$VisibilityChanged),
				$elm$browser$Browser$Events$onKeyDown(
				A2(
					$elm$json$Json$Decode$map,
					$author$project$Mario$Dashboard$GlobalKey,
					A2($elm$json$Json$Decode$field, 'key', $elm$json$Json$Decode$string)))
			]));
};
var $author$project$Mario$Dashboard$ControlAccepted = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$ControlFailed$ = function (a, b) {
	return {$: 3, a: a, b: b};
};
var $author$project$Mario$Dashboard$ControlFailed = F2($author$project$Mario$Dashboard$ControlFailed$);
var $author$project$Mario$Dashboard$ControlPending = function (a) {
	return {$: 1, a: a};
};
var $author$project$Mario$Dashboard$Api$phaseIsLive = function (phase) {
	switch (phase.$) {
		case 1:
			return true;
		case 2:
			return true;
		case 0:
			return true;
		case 3:
			return false;
		case 4:
			return false;
		default:
			return false;
	}
};
var $author$project$Mario$Dashboard$clearSettledControl$ = function (status, control) {
	if (control.$ === 2) {
		switch (control.a) {
			case 0:
				var _v1 = control.a;
				return _Utils_eq(status.bz, $author$project$Mario$Dashboard$Api$Paused) ? $author$project$Mario$Dashboard$ControlIdle : control;
			case 1:
				var _v2 = control.a;
				return $author$project$Mario$Dashboard$Api$phaseIsLive(status.bz) ? $author$project$Mario$Dashboard$ControlIdle : control;
			default:
				var _v3 = control.a;
				return _Utils_eq(status.bz, $author$project$Mario$Dashboard$Api$Stopped) ? $author$project$Mario$Dashboard$ControlIdle : control;
		}
	} else {
		return control;
	}
};
var $author$project$Mario$Dashboard$clearSettledControl = F2($author$project$Mario$Dashboard$clearSettledControl$);
var $author$project$Mario$Dashboard$httpErrorToString = function (error) {
	switch (error.$) {
		case 0:
			var url = error.a;
			return 'bad URL ' + url;
		case 1:
			return 'the request timed out';
		case 2:
			return 'no response from the local trainer';
		case 3:
			var code = error.a;
			return 'the trainer answered with HTTP ' + $elm$core$String$fromInt(code);
		default:
			var detail = error.a;
			return 'the response did not match schema version 4: ' + detail;
	}
};
var $elm$core$Basics$neq = _Utils_notEqual;
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch(_List_Nil);
var $elm$core$Basics$not = _Basics_not;
var $elm$time$Time$posixToMillis = function (_v0) {
	var millis = _v0;
	return millis;
};
var $author$project$Mario$Dashboard$GotControl$ = function (a, b) {
	return {$: 19, a: a, b: b};
};
var $author$project$Mario$Dashboard$GotControl = F2($author$project$Mario$Dashboard$GotControl$);
var $author$project$Mario$Dashboard$actionKey = function (action) {
	switch (action) {
		case 0:
			return 'pause';
		case 1:
			return 'resume';
		default:
			return 'stop';
	}
};
var $author$project$Mario$Dashboard$controlUrl = '/api/control';
var $elm$http$Http$expectBytesResponse$ = function (toMsg, toResult) {
	return A3(
		_Http_expect,
		'arraybuffer',
		_Http_toDataView,
		A2($elm$core$Basics$composeR, toResult, toMsg));
};
var $elm$http$Http$expectBytesResponse = F2($elm$http$Http$expectBytesResponse$);
var $elm$http$Http$expectWhatever = function (toMsg) {
	return $elm$http$Http$expectBytesResponse$(
		toMsg,
		$elm$http$Http$resolve(
			function (_v0) {
				return $elm$core$Result$Ok(0);
			}));
};
var $elm$http$Http$jsonBody = function (value) {
	return A2(
		_Http_pair,
		'application/json',
		A2($elm$json$Json$Encode$encode, 0, value));
};
var $elm$json$Json$Encode$object = function (pairs) {
	return _Json_wrap(
		$elm$core$List$foldl$(
			F2(
				function (_v0, obj) {
					var k = _v0.a;
					var v = _v0.b;
					return A3(_Json_addField, k, v, obj);
				}),
			_Json_emptyObject(0),
			pairs));
};
var $elm$json$Json$Encode$string = _Json_wrap;
var $author$project$Mario$Dashboard$sendControl = function (action) {
	return $elm$http$Http$request(
		{
			hk: $elm$http$Http$jsonBody(
				$elm$json$Json$Encode$object(
					_List_fromArray(
						[
							_Utils_Tuple2(
							'action',
							$elm$json$Json$Encode$string(
								$author$project$Mario$Dashboard$actionKey(action)))
						]))),
			hI: $elm$http$Http$expectWhatever(
				$author$project$Mario$Dashboard$GotControl(action)),
			hO: _List_Nil,
			ik: 'POST',
			jf: $author$project$Mario$Dashboard$requestTimeout,
			jn: $elm$core$Maybe$Nothing,
			jr: $author$project$Mario$Dashboard$controlUrl
		});
};
var $author$project$Mario$Dashboard$update$ = function (msg, model) {
	switch (msg.$) {
		case 0:
			var now = msg.a;
			var age = function () {
				var _v1 = model.cL;
				if (!_v1.$) {
					var at = _v1.a;
					return ($elm$time$Time$posixToMillis(now) - $elm$time$Time$posixToMillis(at)) / 1000;
				} else {
					return model.bi;
				}
			}();
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{aX: true, dj: now, bi: age}),
				model.aX ? $elm$core$Platform$Cmd$none : $author$project$Mario$Dashboard$fetchStatus);
		case 1:
			if (!msg.a.$) {
				var status = msg.a.a;
				var needsNetwork = (!_Utils_eq(status.eJ.e1, $elm$core$Maybe$Nothing)) && (!_Utils_eq(model.df, status.eJ.e1));
				var control = $author$project$Mario$Dashboard$clearSettledControl$(status, model.aV);
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aV: control,
							b7: 0,
							aX: false,
							bw: model.bw || needsNetwork,
							cL: $elm$core$Maybe$Just(model.dj),
							cM: true,
							aI: $elm$core$Maybe$Just(status),
							bi: 0,
							bj: $elm$core$Maybe$Nothing
						}),
					(needsNetwork && (!model.bw)) ? $author$project$Mario$Dashboard$fetchNetwork : $elm$core$Platform$Cmd$none);
			} else {
				var error = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							b7: model.b7 + 1,
							aX: false,
							cM: true,
							bj: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$httpErrorToString(error))
						}),
					$elm$core$Platform$Cmd$none);
			}
		case 2:
			if (!msg.a.$) {
				var network = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cE: $elm$core$Maybe$Just(network),
							cF: $elm$core$Maybe$Nothing,
							df: network.dF,
							bw: false
						}),
					$elm$core$Platform$Cmd$none);
			} else {
				var error = msg.a.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							cF: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$httpErrorToString(error)),
							bw: false
						}),
					$elm$core$Platform$Cmd$none);
			}
		case 3:
			var visibility = msg.a;
			var visible = !visibility;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{aX: visible || model.aX, cW: visible}),
				visible ? $author$project$Mario$Dashboard$fetchStatus : $elm$core$Platform$Cmd$none);
		case 4:
			if (msg.a === 'Escape') {
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{a1: $elm$core$Maybe$Nothing, bC: $elm$core$Maybe$Nothing}),
					$elm$core$Platform$Cmd$none);
			} else {
				return _Utils_Tuple2(model, $elm$core$Platform$Cmd$none);
			}
		case 5:
			var tipId = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						a1: $elm$core$Maybe$Just(tipId)
					}),
				$elm$core$Platform$Cmd$none);
		case 6:
			var tipId = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						a1: _Utils_eq(
							model.a1,
							$elm$core$Maybe$Just(tipId)) ? $elm$core$Maybe$Nothing : model.a1
					}),
				$elm$core$Platform$Cmd$none);
		case 7:
			var tipId = msg.a;
			return _Utils_eq(
				model.bC,
				$elm$core$Maybe$Just(tipId)) ? _Utils_Tuple2(
				_Utils_update(
					model,
					{a1: $elm$core$Maybe$Nothing, bC: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none) : _Utils_Tuple2(
				_Utils_update(
					model,
					{
						a1: $elm$core$Maybe$Just(tipId),
						bC: $elm$core$Maybe$Just(tipId)
					}),
				$elm$core$Platform$Cmd$none);
		case 8:
			var index = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						cX: $elm$core$Maybe$Just(index)
					}),
				$elm$core$Platform$Cmd$none);
		case 9:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{cX: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 10:
			var index = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						cO: $elm$core$Maybe$Just(index)
					}),
				$elm$core$Platform$Cmd$none);
		case 11:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{cO: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 12:
			var index = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						cI: $elm$core$Maybe$Just(index)
					}),
				$elm$core$Platform$Cmd$none);
		case 13:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{cI: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 14:
			var row = msg.a;
			var col = msg.b;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						cw: $elm$core$Maybe$Just(
							_Utils_Tuple2(row, col))
					}),
				$elm$core$Platform$Cmd$none);
		case 15:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{cw: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 16:
			var id = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						cH: $elm$core$Maybe$Just(id)
					}),
				$elm$core$Platform$Cmd$none);
		case 17:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{cH: $elm$core$Maybe$Nothing}),
				$elm$core$Platform$Cmd$none);
		case 18:
			var action = msg.a;
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{
						aV: $author$project$Mario$Dashboard$ControlPending(action)
					}),
				$author$project$Mario$Dashboard$sendControl(action));
		case 19:
			if (!msg.b.$) {
				var action = msg.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aV: $author$project$Mario$Dashboard$ControlAccepted(action),
							aX: true
						}),
					$author$project$Mario$Dashboard$fetchStatus);
			} else {
				var action = msg.a;
				var error = msg.b.a;
				return _Utils_Tuple2(
					_Utils_update(
						model,
						{
							aV: $author$project$Mario$Dashboard$ControlFailed$(
								action,
								$author$project$Mario$Dashboard$httpErrorToString(error))
						}),
					$elm$core$Platform$Cmd$none);
			}
		default:
			return _Utils_Tuple2(
				_Utils_update(
					model,
					{aX: true, bw: true}),
				$elm$core$Platform$Cmd$batch(
					_List_fromArray(
						[$author$project$Mario$Dashboard$fetchStatus, $author$project$Mario$Dashboard$fetchNetwork])));
	}
};
var $author$project$Mario$Dashboard$update = F2($author$project$Mario$Dashboard$update$);
var $elm$html$Html$Attributes$stringProperty$ = function (key, string) {
	return A2(
		_VirtualDom_property,
		key,
		$elm$json$Json$Encode$string(string));
};
var $elm$html$Html$Attributes$stringProperty = F2($elm$html$Html$Attributes$stringProperty$);
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $elm$html$Html$div = _VirtualDom_node('div');
var $author$project$Mario$Dashboard$RequestControl = function (a) {
	return {$: 18, a: a};
};
var $author$project$Mario$Dashboard$actionLabel = function (action) {
	switch (action) {
		case 0:
			return 'Pause';
		case 1:
			return 'Resume';
		default:
			return 'Stop';
	}
};
var $elm$virtual_dom$VirtualDom$attribute$ = function (key, value) {
	return A2(
		_VirtualDom_attribute,
		_VirtualDom_noOnOrFormAction(key),
		_VirtualDom_noJavaScriptOrHtmlUri(value));
};
var $elm$virtual_dom$VirtualDom$attribute = F2($elm$virtual_dom$VirtualDom$attribute$);
var $elm$html$Html$Attributes$attribute = $elm$virtual_dom$VirtualDom$attribute;
var $elm$html$Html$button = _VirtualDom_node('button');
var $elm$virtual_dom$VirtualDom$Normal = function (a) {
	return {$: 0, a: a};
};
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$on$ = function (event, decoder) {
	return A2(
		$elm$virtual_dom$VirtualDom$on,
		event,
		$elm$virtual_dom$VirtualDom$Normal(decoder));
};
var $elm$html$Html$Events$on = F2($elm$html$Html$Events$on$);
var $elm$html$Html$Events$onClick = function (msg) {
	return $elm$html$Html$Events$on$(
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$strong = _VirtualDom_node('strong');
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $author$project$Mario$Dashboard$controlBanner = function (model) {
	var _v0 = model.aV;
	switch (_v0.$) {
		case 3:
			var action = _v0.a;
			var reason = _v0.b;
			return $elm$core$Maybe$Just(
				A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('banner banner-bad'),
							A2($elm$html$Html$Attributes$attribute, 'role', 'alert')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$strong,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Mario$Dashboard$actionLabel(action) + ' failed. ')
										])),
									$elm$html$Html$text('The trainer did not accept the request: ' + (reason + '. The run is unchanged.'))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('banner-actions')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$button,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('btn btn-small'),
											$elm$html$Html$Events$onClick(
											$author$project$Mario$Dashboard$RequestControl(action))
										]),
									_List_fromArray(
										[
											$elm$html$Html$text('Try again')
										]))
								]))
						])));
		case 2:
			var action = _v0.a;
			return $elm$core$Maybe$Just(
				A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('banner banner-info'),
							A2($elm$html$Html$Attributes$attribute, 'role', 'status')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$strong,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Mario$Dashboard$actionLabel(action) + ' requested. ')
										])),
									$elm$html$Html$text('The trainer has accepted the request and will act at its next safe boundary. This notice clears when its reported phase confirms it.')
								]))
						])));
		case 1:
			var action = _v0.a;
			return $elm$core$Maybe$Just(
				A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('banner banner-info'),
							A2($elm$html$Html$Attributes$attribute, 'role', 'status')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$html$Html$strong,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Mario$Dashboard$actionLabel(action) + ' sending\u2026 ')
										])),
									$elm$html$Html$text('Waiting for the trainer to acknowledge.')
								]))
						])));
		default:
			return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Mario$Dashboard$RefreshNow = {$: 20};
var $elm$core$Basics$negate = function (n) {
	return -n;
};
var $elm$core$Basics$abs = function (n) {
	return (n < 0) ? (-n) : n;
};
var $elm$core$Basics$min$ = function (x, y) {
	return (_Utils_cmp(x, y) < 0) ? x : y;
};
var $elm$core$Basics$min = F2($elm$core$Basics$min$);
var $elm$core$Basics$modBy = _Basics_modBy;
var $elm$core$String$cons = _String_cons;
var $elm$core$String$fromChar = function (_char) {
	return A2($elm$core$String$cons, _char, '');
};
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightBy = _Bitwise_shiftRightBy;
var $elm$core$String$repeatHelp$ = function (n, chunk, result) {
	return (n <= 0) ? result : $elm$core$String$repeatHelp$(
		n >> 1,
		_Utils_ap(chunk, chunk),
		(!(n & 1)) ? result : _Utils_ap(result, chunk));
};
var $elm$core$String$repeatHelp = F3($elm$core$String$repeatHelp$);
var $elm$core$String$repeat$ = function (n, chunk) {
	return $elm$core$String$repeatHelp$(n, chunk, '');
};
var $elm$core$String$repeat = F2($elm$core$String$repeat$);
var $elm$core$String$padLeft$ = function (n, _char, string) {
	return _Utils_ap(
		$elm$core$String$repeat$(
			n - $elm$core$String$length(string),
			$elm$core$String$fromChar(_char)),
		string);
};
var $elm$core$String$padLeft = F3($elm$core$String$padLeft$);
var $elm$core$Basics$pow = _Basics_pow;
var $elm$core$Basics$round = _Basics_round;
var $author$project$Mario$Dashboard$Format$decimal$ = function (places, value) {
	var safePlaces = $elm$core$Basics$max$(
		0,
		$elm$core$Basics$min$(6, places));
	var scaleInt = A2($elm$core$Basics$pow, 10, safePlaces);
	var magnitude = ($elm$core$Basics$isNaN(value) || $elm$core$Basics$isInfinite(value)) ? 0 : $elm$core$Basics$abs(value);
	var scaled = $elm$core$Basics$round(magnitude * scaleInt);
	var sign = ((value < 0) && (!(!scaled))) ? '-' : '';
	var whole = (scaled / scaleInt) | 0;
	var frac = A2($elm$core$Basics$modBy, scaleInt, scaled);
	var digits = $elm$core$String$padLeft$(
		safePlaces,
		'0',
		$elm$core$String$fromInt(frac));
	return (!safePlaces) ? _Utils_ap(
		sign,
		$elm$core$String$fromInt(whole)) : (sign + ($elm$core$String$fromInt(whole) + ('.' + digits)));
};
var $author$project$Mario$Dashboard$Format$decimal = F2($author$project$Mario$Dashboard$Format$decimal$);
var $author$project$Mario$Dashboard$disconnectedBanner = function (model) {
	var _v0 = _Utils_Tuple2(model.bj, model.aI);
	if ((!_v0.a.$) && (!_v0.b.$)) {
		var reason = _v0.a.a;
		return $elm$core$Maybe$Just(
			A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('banner banner-bad'),
						A2($elm$html$Html$Attributes$attribute, 'role', 'status')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Disconnected. ')
									])),
								$elm$html$Html$text(
								'The last ' + ($elm$core$String$fromInt(model.b7) + (' polls failed: ' + (reason + ('. Everything below is the snapshot from ' + ($author$project$Mario$Dashboard$Format$decimal$(0, model.bi) + ' seconds ago, not the current state of the trainer.'))))))
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('banner-actions')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-small'),
										$elm$html$Html$Events$onClick($author$project$Mario$Dashboard$RefreshNow)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Retry')
									]))
							]))
					])));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Mario$Dashboard$messageBanner = function (model) {
	var _v0 = model.aI;
	if (!_v0.$) {
		var status = _v0.a;
		return $elm$core$String$isEmpty(status.gl) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
			A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('banner'),
						A2($elm$html$Html$Attributes$attribute, 'role', 'status')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text(status.gl)
							]))
					])));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$Maybe$map$ = function (f, maybe) {
	if (!maybe.$) {
		var value = maybe.a;
		return $elm$core$Maybe$Just(
			f(value));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$Maybe$map = F2($elm$core$Maybe$map$);
var $author$project$Mario$Dashboard$staleAfterSeconds = 7;
var $author$project$Mario$Dashboard$isStale = function (model) {
	return (!_Utils_eq(model.bj, $elm$core$Maybe$Nothing)) || ((_Utils_cmp(model.bi, $author$project$Mario$Dashboard$staleAfterSeconds) > 0) || $elm$core$Maybe$withDefault$(
		false,
		$elm$core$Maybe$map$(
			function ($) {
				return $.jd;
			},
			model.aI)));
};
var $author$project$Mario$Dashboard$Api$phaseLabel = function (phase) {
	switch (phase.$) {
		case 0:
			return 'Initializing';
		case 1:
			return 'Training';
		case 2:
			return 'Auditing';
		case 3:
			return 'Paused';
		case 4:
			return 'Stopped';
		default:
			var other = phase.a;
			return other;
	}
};
var $elm$core$String$toLower = _String_toLower;
var $author$project$Mario$Dashboard$staleBanner = function (model) {
	var _v0 = model.aI;
	if (!_v0.$) {
		var status = _v0.a;
		return (_Utils_eq(model.bj, $elm$core$Maybe$Nothing) && ($author$project$Mario$Dashboard$isStale(model) && $author$project$Mario$Dashboard$Api$phaseIsLive(status.bz))) ? $elm$core$Maybe$Just(
			A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('banner banner-warn'),
						A2($elm$html$Html$Attributes$attribute, 'role', 'status')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Stale snapshot. ')
									])),
								$elm$html$Html$text(
								'The trainer says it is ' + ($elm$core$String$toLower(
									$author$project$Mario$Dashboard$Api$phaseLabel(status.bz)) + (', but ' + ((status.jd ? 'it has marked this snapshot stale itself' : ('it has not published an update for ' + ($author$project$Mario$Dashboard$Format$decimal$(0, model.bi) + ' seconds'))) + '. Treat these numbers as historical until it catches up.'))))
							]))
					]))) : $elm$core$Maybe$Nothing;
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Mario$Dashboard$viewBanners = function (model) {
	return $elm$core$List$filterMap$(
		$elm$core$Basics$identity,
		_List_fromArray(
			[
				$author$project$Mario$Dashboard$disconnectedBanner(model),
				$author$project$Mario$Dashboard$staleBanner(model),
				$author$project$Mario$Dashboard$controlBanner(model),
				$author$project$Mario$Dashboard$messageBanner(model)
			]));
};
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $elm$html$Html$section = _VirtualDom_node('section');
var $elm$html$Html$span = _VirtualDom_node('span');
var $author$project$Mario$Dashboard$band$ = function (title, note, panels) {
	return A2(
		$elm$html$Html$section,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('band')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('band-head')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('band-title')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(title)
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('band-note')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(note)
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('grid grid-main')
					]),
				panels)
			]));
};
var $author$project$Mario$Dashboard$band = F3($author$project$Mario$Dashboard$band$);
var $author$project$Mario$Dashboard$TipClose = function (a) {
	return {$: 6, a: a};
};
var $author$project$Mario$Dashboard$TipOpen = function (a) {
	return {$: 5, a: a};
};
var $author$project$Mario$Dashboard$TipToggle = function (a) {
	return {$: 7, a: a};
};
var $author$project$Mario$Dashboard$tipHandlers = function (model) {
	return {
		jT: $author$project$Mario$Dashboard$TipClose,
		kO: $author$project$Mario$Dashboard$TipOpen,
		kP: function () {
			var _v0 = model.bC;
			if (!_v0.$) {
				var pinned = _v0.a;
				return $elm$core$Maybe$Just(pinned);
			} else {
				return model.a1;
			}
		}(),
		kU: model.bC,
		lp: $author$project$Mario$Dashboard$TipToggle
	};
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
var $elm$core$List$isEmpty = function (xs) {
	if (!xs.b) {
		return true;
	} else {
		return false;
	}
};
var $elm$html$Html$p = _VirtualDom_node('p');
var $author$project$Mario$Dashboard$Tip$AlignStart = 0;
var $author$project$Mario$Dashboard$Tip$bubbleId = function (t) {
	return 'tip-' + t.e1;
};
var $elm$html$Html$Attributes$type_ = $elm$html$Html$Attributes$stringProperty('type');
var $author$project$Mario$Dashboard$Tip$dismiss$ = function (handlers, t) {
	return _Utils_eq(
		handlers.kU,
		$elm$core$Maybe$Just(t.e1)) ? _List_fromArray(
		[
			A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('tip-dismiss')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('button'),
							$elm$html$Html$Attributes$class('btn btn-small'),
							$elm$html$Html$Events$onClick(
							handlers.lp(t.e1))
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Dismiss')
						]))
				]))
		]) : _List_Nil;
};
var $author$project$Mario$Dashboard$Tip$dismiss = F2($author$project$Mario$Dashboard$Tip$dismiss$);
var $elm$html$Html$Attributes$id = $elm$html$Html$Attributes$stringProperty('id');
var $author$project$Mario$Dashboard$Tip$isOpen$ = function (handlers, t) {
	return _Utils_eq(
		handlers.kP,
		$elm$core$Maybe$Just(t.e1));
};
var $author$project$Mario$Dashboard$Tip$isOpen = F2($author$project$Mario$Dashboard$Tip$isOpen$);
var $elm$html$Html$b = _VirtualDom_node('b');
var $author$project$Mario$Dashboard$Tip$metaLine = function (_v0) {
	var key = _v0.a;
	var value = _v0.b;
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('tip-meta')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$b,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(key + ': ')
					])),
				$elm$html$Html$text(value)
			]));
};
var $author$project$Mario$Dashboard$Tip$bubble$ = function (handlers, align, t) {
	return $author$project$Mario$Dashboard$Tip$isOpen$(handlers, t) ? A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class(
				'tip-bubble' + function () {
					if (align === 1) {
						return ' tip-align-end';
					} else {
						return '';
					}
				}()),
				$elm$html$Html$Attributes$id(
				$author$project$Mario$Dashboard$Tip$bubbleId(t)),
				A2($elm$html$Html$Attributes$attribute, 'role', 'tooltip')
			]),
		A2(
			$elm$core$List$cons,
			A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('tip-title')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(t.ds)
					])),
			A2(
				$elm$core$List$cons,
				$elm$html$Html$text(t.hk),
				_Utils_ap(
					$elm$core$List$map$($author$project$Mario$Dashboard$Tip$metaLine, t.d4),
					$author$project$Mario$Dashboard$Tip$dismiss$(handlers, t))))) : $elm$html$Html$text('');
};
var $author$project$Mario$Dashboard$Tip$bubble = F3($author$project$Mario$Dashboard$Tip$bubble$);
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
var $elm$html$Html$Events$onBlur = function (msg) {
	return $elm$html$Html$Events$on$(
		'blur',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$Events$onFocus = function (msg) {
	return $elm$html$Html$Events$on$(
		'focus',
		$elm$json$Json$Decode$succeed(msg));
};
var $author$project$Mario$Dashboard$Tip$trigger$ = function (handlers, t) {
	return A2(
		$elm$html$Html$button,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$type_('button'),
				$elm$html$Html$Attributes$class('tip-trigger'),
				A2($elm$html$Html$Attributes$attribute, 'aria-label', 'Explain: ' + t.ds),
				A2(
				$elm$html$Html$Attributes$attribute,
				'aria-expanded',
				$author$project$Mario$Dashboard$Tip$isOpen$(handlers, t) ? 'true' : 'false'),
				A2(
				$elm$html$Html$Attributes$attribute,
				'aria-describedby',
				$author$project$Mario$Dashboard$Tip$bubbleId(t)),
				$elm$html$Html$Events$onFocus(
				handlers.kO(t.e1)),
				$elm$html$Html$Events$onBlur(
				handlers.jT(t.e1)),
				$elm$html$Html$Events$onClick(
				handlers.lp(t.e1))
			]),
		_List_fromArray(
			[
				$elm$html$Html$text('?')
			]));
};
var $author$project$Mario$Dashboard$Tip$trigger = F2($author$project$Mario$Dashboard$Tip$trigger$);
var $author$project$Mario$Dashboard$Tip$view$ = function (handlers, align, t, content) {
	return A2(
		$elm$html$Html$span,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('tip'),
				$elm$html$Html$Events$onMouseEnter(
				handlers.kO(t.e1)),
				$elm$html$Html$Events$onMouseLeave(
				handlers.jT(t.e1))
			]),
		_Utils_ap(
			content,
			_List_fromArray(
				[
					$author$project$Mario$Dashboard$Tip$trigger$(handlers, t),
					$author$project$Mario$Dashboard$Tip$bubble$(handlers, align, t)
				])));
};
var $author$project$Mario$Dashboard$Tip$view = F4($author$project$Mario$Dashboard$Tip$view$);
var $author$project$Mario$Dashboard$panel$ = function (tips, tip, title, children) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('panel')
			]),
		A2(
			$elm$core$List$cons,
			A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel-head')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						tip,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(title)
									]))
							]))
					])),
			children));
};
var $author$project$Mario$Dashboard$panel = F4($author$project$Mario$Dashboard$panel$);
var $author$project$Mario$Dashboard$Tip$tip$ = function (tipId, title, body, meta) {
	return {hk: body, e1: tipId, d4: meta, ds: title};
};
var $author$project$Mario$Dashboard$Tip$tip = F4($author$project$Mario$Dashboard$Tip$tip$);
var $author$project$Mario$Dashboard$Copy$t = $author$project$Mario$Dashboard$Tip$tip;
var $author$project$Mario$Dashboard$Copy$sampleAllocation = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'allocation',
	'Training sample allocation',
	'How the next generation\'s training panel is weighted across the 625 cells. The mixture deliberately favours cells with little evidence and cells whose outcome is still close, while a coverage floor keeps every cell rehearsed so none is forgotten. Both seat orientations are represented. Every population member is scored on the same sampled panel in a generation, and when the panel changes, elites are rescored rather than keeping a stale fitness.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Share of total sampling weight across all 625 cells.'),
			_Utils_Tuple2('Window', 'The upcoming generation\'s panel.'),
			_Utils_Tuple2('Source', 'Training sampler. Training seeds are separate from gate seeds, and these weights do not feed the gate.')
		]));
var $elm$core$Basics$clamp$ = function (low, high, number) {
	return (_Utils_cmp(number, low) < 0) ? low : ((_Utils_cmp(number, high) > 0) ? high : number);
};
var $elm$core$Basics$clamp = F3($elm$core$Basics$clamp$);
var $author$project$Mario$Dashboard$Format$percent1 = function (value) {
	return $author$project$Mario$Dashboard$Format$decimal$(1, value * 100) + '%';
};
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $author$project$Mario$Dashboard$shareRow$ = function (name, chip, share) {
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('alloc-name')
					]),
				A2(
					$elm$core$List$cons,
					A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('who')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(name)
							])),
					function () {
						if (!chip.$) {
							var label = chip.a;
							return _List_fromArray(
								[
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('chip')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(label)
										]))
								]);
						} else {
							return _List_Nil;
						}
					}())),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('alloc-row')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('alloc-bar')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('alloc-fill'),
										A2(
										$elm$html$Html$Attributes$style,
										'width',
										$author$project$Mario$Dashboard$Format$decimal$(
											2,
											$elm$core$Basics$clamp$(0, 1, share) * 100) + '%')
									]),
								_List_Nil)
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('alloc-share')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$author$project$Mario$Dashboard$Format$percent1(share))
							]))
					]))
			]));
};
var $author$project$Mario$Dashboard$shareRow = F3($author$project$Mario$Dashboard$shareRow$);
var $elm$core$List$sortBy = _List_sortBy;
var $elm$core$List$sum = function (numbers) {
	return $elm$core$List$foldl$($elm$core$Basics$add, 0, numbers);
};
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
var $author$project$Mario$Dashboard$viewAllocation$ = function (tips, status) {
	var total = $elm$core$List$sum(
		$elm$core$List$map$(
			function ($) {
				return $.fk;
			},
			status.dd));
	var top = $elm$core$List$filter$(
		function (m) {
			return m.fk > 0;
		},
		$elm$core$List$take$(
			10,
			A2(
				$elm$core$List$sortBy,
				function (m) {
					return -m.fk;
				},
				status.dd)));
	var row = function (matchup) {
		return $author$project$Mario$Dashboard$shareRow$(
			'our ' + (matchup.lx + (' vs their ' + matchup.ln)),
			$elm$core$Maybe$Just(
				$author$project$Mario$Dashboard$Format$decimal$(1, matchup.lr) + ' games'),
			(total <= 0) ? 0 : (matchup.fk / total));
	};
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$sampleAllocation,
		'Training sample allocation',
		_List_fromArray(
			[
				$elm$core$List$isEmpty(top) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('placeholder')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('No weights published')
							])),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('The sampler has not reported per-cell weights for the upcoming generation.')
							]))
					])) : A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('alloc')
					]),
				$elm$core$List$map$(row, top)),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Weights are a deterministic mixture: a floor that keeps every cell rehearsed, a term that favours cells with little evidence, and a term that favours cells whose outcome is still close. Both seat orientations are sampled.')
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Every population member plays the same sampled panel within a generation, so their scores are comparable with each other. When the panel changes, elites are rescored rather than carrying a fitness earned on a different panel.')
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('These weights steer training play only. Gate evidence comes from separate balanced panels on separate seeds, and nothing here feeds it.')
					]))
			]));
};
var $author$project$Mario$Dashboard$viewAllocation = F2($author$project$Mario$Dashboard$viewAllocation$);
var $author$project$Mario$Dashboard$Copy$benchmark = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'benchmark',
	'Benchmark reference',
	'What this exact binary costs on the fixed benchmark workload, taken as the BEST of several repetitions because unrelated load can only ever make a repetition slower. It is quoted only for recorded runs of this build on this workload definition, so a figure from another binary or another task list can never be compared with it by accident. It does not move while the trainer runs.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Display ticks and link activations of the fixed task list.'),
			_Utils_Tuple2('Window', 'One recorded benchmark run, single threaded, with no duty governor and no nice.'),
			_Utils_Tuple2('Source', 'The append-only bench history beside this run. Absent until this build has been benchmarked.')
		]));
var $author$project$Mario$Dashboard$benchmarkComparison = function (status) {
	var _v0 = _Utils_Tuple2(
		$elm$core$Maybe$andThen$(
			function ($) {
				return $.eN;
			},
			status.hh),
		$elm$core$Maybe$andThen$(
			function ($) {
				return $.eN;
			},
			status.jw));
	if ((!_v0.a.$) && (!_v0.b.$)) {
		var recorded = _v0.a.a;
		var live = _v0.b.a;
		return (recorded <= 0) ? 'The recorded benchmark reports no cost per tick, so there is nothing to compare the live rate against.' : ('This session is running at ' + ($author$project$Mario$Dashboard$Format$decimal$(2, live / recorded) + 'x the recorded cost per simulated tick. Above one is the price of sharing the machine and of spilling workers onto slower cores; it is not a change in the build.'));
	} else {
		return 'A live rate and a recorded rate are both needed to compare them, and one of the two has not been measured.';
	}
};
var $elm$html$Html$dd = _VirtualDom_node('dd');
var $elm$html$Html$dl = _VirtualDom_node('dl');
var $elm$html$Html$dt = _VirtualDom_node('dt');
var $author$project$Mario$Dashboard$Format$awaiting = 'Awaiting evidence';
var $author$project$Mario$Dashboard$viewMetric$ = function (tips, spec) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('metric ' + spec.u)
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metric-label')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						spec.w,
						_List_fromArray(
							[
								$elm$html$Html$text(spec.n)
							]))
					])),
				function () {
				var _v0 = spec.r;
				if (!_v0.$) {
					var value = _v0.a;
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('metric-value')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(value)
							]));
				} else {
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('metric-value is-unknown')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text($author$project$Mario$Dashboard$Format$awaiting)
							]));
				}
			}(),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metric-sub')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(spec.v)
					]))
			]));
};
var $author$project$Mario$Dashboard$viewMetric = F2($author$project$Mario$Dashboard$viewMetric$);
var $author$project$Mario$Dashboard$viewBenchmark$ = function (tips, status) {
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$benchmark,
		'Benchmark reference',
		function () {
			var _v0 = status.hh;
			if (_v0.$ === 1) {
				return _List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('placeholder')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Not benchmarked')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('No fixed-work benchmark has been recorded for this build. Run melee-mario bench to record one; until then there is nothing to read the live rates against.')
									]))
							]))
					]);
			} else {
				var recorded = _v0.a;
				return _List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('metrics')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewMetric$(
								tips,
								{
									u: 'metric-cyan',
									n: 'Best of N',
									v: 'fastest of ' + ($elm$core$Maybe$withDefault$(
										'several',
										$elm$core$Maybe$map$($elm$core$String$fromInt, recorded.k1)) + (' repetitions over ' + ($elm$core$Maybe$withDefault$(
										'the',
										$elm$core$Maybe$map$($elm$core$String$fromInt, recorded.kb)) + ' fixed fights'))),
									w: $author$project$Mario$Dashboard$Copy$benchmark,
									r: $elm$core$Maybe$map$(
										function (s) {
											return $author$project$Mario$Dashboard$Format$decimal$(3, s) + 's';
										},
										recorded.jK)
								}),
								$author$project$Mario$Dashboard$viewMetric$(
								tips,
								{
									u: '',
									n: 'CPU ns / tick',
									v: 'single threaded, no duty governor, no nice',
									w: $author$project$Mario$Dashboard$Copy$benchmark,
									r: $elm$core$Maybe$map$(
										$author$project$Mario$Dashboard$Format$decimal(1),
										recorded.eN)
								}),
								$author$project$Mario$Dashboard$viewMetric$(
								tips,
								{
									u: '',
									n: 'CPU ns / link',
									v: 'same quantity the live figure reports',
									w: $author$project$Mario$Dashboard$Copy$benchmark,
									r: $elm$core$Maybe$map$(
										$author$project$Mario$Dashboard$Format$decimal(2),
										recorded.hw)
								})
							])),
						A2(
						$elm$html$Html$dl,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('deflist'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Recorded')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$Maybe$withDefault$('time not reported', recorded.he) + (' \u00B7 best of ' + ($elm$core$String$fromInt(recorded.hu) + (' comparable ' + ((recorded.hu === 1) ? 'result' : 'results')))))
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Workload')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$Maybe$withDefault$('not reported', recorded.j_))
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Build')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$Maybe$withDefault$('not reported', recorded.jM))
									]))
							])),
						A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('prose'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '12px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$author$project$Mario$Dashboard$benchmarkComparison(status))
							]))
					]);
			}
		}());
};
var $author$project$Mario$Dashboard$viewBenchmark = F2($author$project$Mario$Dashboard$viewBenchmark$);
var $elm$core$List$head = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(x);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$core$String$replace$ = function (before, after, string) {
	return $elm$core$String$join$(
		after,
		$elm$core$String$split$(before, string));
};
var $elm$core$String$replace = F3($elm$core$String$replace$);
var $author$project$Mario$Dashboard$Format$timeOfDay = function (iso) {
	var _v0 = $elm$core$String$split$('T', iso);
	if ((_v0.b && _v0.b.b) && (!_v0.b.b.b)) {
		var _v1 = _v0.b;
		var rest = _v1.a;
		return $elm$core$Maybe$withDefault$(
			rest,
			$elm$core$List$head(
				$elm$core$String$split$(
					'.',
					$elm$core$String$replace$('Z', '', rest))));
	} else {
		return iso;
	}
};
var $author$project$Mario$Dashboard$Copy$timeline = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'timeline',
	'Run events',
	'Notable transitions the trainer recorded: promotions, audits started and finished, checkpoints, pauses and errors. This is the run\'s own account of what happened, in its own clock.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a list.'),
			_Utils_Tuple2('Window', 'The most recent events the trainer retains.'),
			_Utils_Tuple2('Source', 'Trainer event log.')
		]));
var $author$project$Mario$Dashboard$viewEvents$ = function (tips, status) {
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$timeline,
		'Run events',
		_List_fromArray(
			[
				$elm$core$List$isEmpty(status.hH) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('placeholder')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('No events')
							])),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('The trainer has not recorded any notable transitions in this run yet.')
							]))
					])) : A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('events')
					]),
				$elm$core$List$map$(
					function (event) {
						return A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('event-row')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('event-at')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Mario$Dashboard$Format$timeOfDay(event.he))
										])),
									A2(
									$elm$html$Html$span,
									_List_Nil,
									_List_fromArray(
										[
											$elm$html$Html$text(event.gl)
										]))
								]));
					},
					$elm$core$List$reverse(status.hH)))
			]));
};
var $author$project$Mario$Dashboard$viewEvents = F2($author$project$Mario$Dashboard$viewEvents$);
var $author$project$Mario$Dashboard$Copy$championId = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'champion-id',
	'Current champion',
	'The genome whose audit evidence is shown on this page. Audit evidence belongs to one specific champion fingerprint. When the champion changes, evidence gathered for the previous one is discarded rather than pooled, so a fresh champion legitimately starts again at no samples.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; an identity.'),
			_Utils_Tuple2('Window', 'Current as of the last poll.'),
			_Utils_Tuple2('Source', 'Frozen candidate under audit.')
		]));
var $author$project$Mario$Dashboard$Tip$detail$ = function (base, lines) {
	return $elm$core$List$isEmpty(lines) ? base : _Utils_update(
		base,
		{
			hk: $elm$core$String$join$(
				' ',
				A2($elm$core$List$cons, base.hk, lines))
		});
};
var $author$project$Mario$Dashboard$Tip$detail = F2($author$project$Mario$Dashboard$Tip$detail$);
var $author$project$Mario$Dashboard$Scoring$criterion = function (scoring) {
	if (scoring.$ === 1) {
		return $author$project$Mario$Dashboard$Api$CombatWins;
	} else {
		var reported = scoring.a;
		return reported.eZ;
	}
};
var $author$project$Mario$Dashboard$Scoring$explainGate = function (scoring) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
	switch (_v0.$) {
		case 0:
			return _List_fromArray(
				['This gate counts actual combat wins: fights our champion resolved in its favour. A fight that reaches the cut-off unresolved is not a win and counts against the rate.']);
		case 1:
			return _List_fromArray(
				['This gate counts strict crew-share leads, not wins. A game counts when our surviving share of our starting crew is strictly greater than theirs, compared as an exact ratio rather than as rounded percentages.', 'A fight that reaches the cut-off with both ships still flying is eligible and counts whenever our share is ahead. Every figure gathered under this gate is therefore a count of leads, and none of them is a count of wins.', 'Ties do not count, including the case where both crews are at zero. A dead heat fails the gate rather than half-passing it.']);
		default:
			var other = _v0.a;
			return _List_fromArray(
				['This run reports its gate criterion as \"' + (other + '\", which this dashboard does not recognise. The counted figures are shown as published and are not described as wins.')]);
	}
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
var $author$project$Mario$Dashboard$Format$chunk3 = function (chars) {
	if (!chars.b) {
		return _List_Nil;
	} else {
		return A2(
			$elm$core$List$cons,
			$elm$core$List$take$(3, chars),
			$author$project$Mario$Dashboard$Format$chunk3(
				$elm$core$List$drop$(3, chars)));
	}
};
var $elm$core$String$fromList = _String_fromList;
var $elm$core$String$reverse = _String_reverse;
var $elm$core$String$foldr = _String_foldr;
var $elm$core$String$toList = function (string) {
	return A3($elm$core$String$foldr, $elm$core$List$cons, _List_Nil, string);
};
var $author$project$Mario$Dashboard$Format$count = function (value) {
	var sign = (value < 0) ? '-' : '';
	var digits = $elm$core$String$fromInt(
		$elm$core$Basics$abs(value));
	var grouped = $elm$core$String$reverse(
		$elm$core$String$join$(
			',',
			$elm$core$List$map$(
				$elm$core$String$fromList,
				$author$project$Mario$Dashboard$Format$chunk3(
					$elm$core$String$toList(
						$elm$core$String$reverse(digits))))));
	return _Utils_ap(sign, grouped);
};
var $author$project$Mario$Dashboard$Format$percent = function (value) {
	return $author$project$Mario$Dashboard$Format$decimal$(0, value * 100) + '%';
};
var $author$project$Mario$Dashboard$Scoring$rateLabel = function (scoring) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
	switch (_v0.$) {
		case 0:
			return 'win rate';
		case 1:
			return 'crew-lead rate';
		default:
			return 'gate success rate';
	}
};
var $author$project$Mario$Dashboard$Gate$seatCoverage = function (rows) {
	var inSeat = function (seat) {
		return $elm$core$List$filter$(
			function (r) {
				return _Utils_eq(r.ld, seat);
			},
			rows);
	};
	return {
		gw: $elm$core$List$length(
			inSeat($author$project$Mario$Dashboard$Api$OpponentSeat)),
		gy: $elm$core$List$length(
			$elm$core$List$filter$(
				function (r) {
					return r.ay > 0;
				},
				inSeat($author$project$Mario$Dashboard$Api$OpponentSeat))),
		gz: $elm$core$List$length(
			inSeat($author$project$Mario$Dashboard$Api$OurSeat)),
		gA: $elm$core$List$length(
			$elm$core$List$filter$(
				function (r) {
					return r.ay > 0;
				},
				inSeat($author$project$Mario$Dashboard$Api$OurSeat)))
	};
};
var $elm$core$String$right$ = function (n, string) {
	return (n < 1) ? '' : A3(
		$elm$core$String$slice,
		-n,
		$elm$core$String$length(string),
		string);
};
var $elm$core$String$right = F2($elm$core$String$right$);
var $author$project$Mario$Dashboard$Format$shortId = function (raw) {
	return ($elm$core$String$length(raw) <= 20) ? raw : ($elm$core$String$left$(10, raw) + ('\u2026' + $elm$core$String$right$(6, raw)));
};
var $author$project$Mario$Dashboard$Api$gateSuccessPlural = function (criterion) {
	switch (criterion.$) {
		case 0:
			return 'wins';
		case 1:
			return 'crew leads';
		default:
			return 'counted successes';
	}
};
var $author$project$Mario$Dashboard$Scoring$successPlural = function (scoring) {
	return $author$project$Mario$Dashboard$Api$gateSuccessPlural(
		$author$project$Mario$Dashboard$Scoring$criterion(scoring));
};
var $author$project$Mario$Dashboard$Gate$explainOverall$ = function (scoring, board, maybeOverall, ships) {
	var timeoutLine = function () {
		var _v7 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
		if (_v7.$ === 1) {
			return 'Every game on the panel counts, including games that end unresolved. Those are scored on crew share like any other, so an unresolved game can count for this gate as readily as a resolved one, and none is dropped.';
		} else {
			return 'Every game on the panel counts, including games that time out. Those are counted as non-wins, so the figure cannot be flattered by dropping unresolved fights.';
		}
	}();
	var target = function () {
		if (!maybeOverall.$) {
			var overall = maybeOverall.a;
			return overall.aJ;
		} else {
			return 0.8;
		}
	}();
	var sourceLine = 'Both groupings count our champion\'s own ' + ($author$project$Mario$Dashboard$Scoring$successPlural(scoring) + ': one grouped by the hull it was piloting, the other by the hull it was facing. Neither is the enemy\'s count. All of it is this frozen champion\'s balanced-evaluation evidence only, never an earlier champion\'s and never adaptive training play.');
	var roundLine = function () {
		if (maybeOverall.$ === 1) {
			return 'No overall panel result has been published yet, so the gate cannot be judged. That is an absence of evidence, not a score of zero.';
		} else {
			var overall = maybeOverall.a;
			var _v3 = overall.gK;
			if (!_v3.$) {
				switch (_v3.a.$) {
					case 0:
						var _v4 = _v3.a;
						return 'This is the audit round. A pass here is provisional: the same frozen champion then has to repeat it on an independent confirm panel with its own trial counter before the gate is cleared.';
					case 1:
						var _v5 = _v3.a;
						return 'This is the independent confirm round, played by the same frozen champion on a separate panel with its own trial counter after the audit round passed.';
					default:
						var other = _v3.a.a;
						return 'The trainer reports the round as \"' + (other + '\", which this dashboard does not recognise. The figures are shown as published.');
				}
			} else {
				return 'No gate round is running. These figures are the last published panel result, not a live attempt.';
			}
		}
	}();
	var readinessSourceLine = $elm$core$List$any$(
		function (r) {
			return _Utils_eq(r.ja, $author$project$Mario$Dashboard$Api$FromReadiness);
		},
		ships) ? _List_fromArray(
		['The per-hull rows currently come from the cheap balanced readiness probe, not from a gate round. A readiness result decides when an audit is worth spending; it is not audit evidence and nothing is gated on it.']) : _List_Nil;
	var rate = $author$project$Mario$Dashboard$Scoring$rateLabel(scoring);
	var scopeLine = 'The run is judged on one number: the frozen champion\'s ' + (rate + (' over a fixed held-out balanced panel in which every hull appears equally often on both sides, and every pair is played in both seats. The target is ' + ($author$project$Mario$Dashboard$Format$percent(target) + ' overall.')));
	var inheritedLine = function () {
		if (!maybeOverall.$) {
			var overall = maybeOverall.a;
			var _v1 = _Utils_Tuple3(overall.gB, overall.kS, overall.dF);
			if (((!_v1.a) && (!_v1.b.$)) && (!_v1.c.$)) {
				var cleared = _v1.b.a;
				var current = _v1.c.a;
				return (!_Utils_eq(cleared, current)) ? _List_fromArray(
					[
						'The target was cleared by champion ' + ($author$project$Mario$Dashboard$Format$shortId(cleared) + (', which is no longer the champion. That result belongs to that policy and is not inherited by ' + ($author$project$Mario$Dashboard$Format$shortId(current) + '.')))
					]) : _List_Nil;
			} else {
				return _List_Nil;
			}
		} else {
			return _List_Nil;
		}
	}();
	var coverage = $author$project$Mario$Dashboard$Gate$seatCoverage(ships);
	var coverageLine = $elm$core$List$isEmpty(ships) ? _List_Nil : (((_Utils_cmp(coverage.gA, coverage.gz) < 0) || (_Utils_cmp(coverage.gy, coverage.gw) < 0)) ? _List_fromArray(
		[
			'Per-hull evidence is incomplete: ' + ($elm$core$String$fromInt(coverage.gA) + (' of ' + ($elm$core$String$fromInt(coverage.gz) + (' hulls flying for us and ' + ($elm$core$String$fromInt(coverage.gy) + (' of ' + ($elm$core$String$fromInt(coverage.gw) + ' hulls it has faced have games on this panel. The rest are unmeasured, which is not the same as losing.')))))))
		]) : _List_fromArray(
		['Every hull reported carries games in both groupings on this panel.']));
	var correlationLine = 'Each pair is played in both seats, so the outcomes on the panel are correlated rather than independent. Treat the bound as an operational confidence check on this distribution, not as a formal guarantee over every matchup.';
	var boardLine = 'All ' + ($author$project$Mario$Dashboard$Format$count(board.ji) + ' ordered matchups are trained on from generation one. Nothing is unlocked a few ships at a time, so no cell has a gate of its own and none is waiting its turn.');
	var aggregateLine = 'That is an aggregate over the whole distribution. It is not a claim that the champion clears ' + ($author$project$Mario$Dashboard$Format$percent(target) + ' in every matchup, and the per-hull figures below exist precisely to show where it does not.');
	return _Utils_ap(
		_List_fromArray(
			[scopeLine, boardLine, aggregateLine, correlationLine, roundLine]),
		_Utils_ap(
			coverageLine,
			_Utils_ap(
				_List_fromArray(
					[sourceLine]),
				_Utils_ap(
					readinessSourceLine,
					_Utils_ap(
						_List_fromArray(
							[timeoutLine]),
						inheritedLine)))));
};
var $author$project$Mario$Dashboard$Gate$explainOverall = F4($author$project$Mario$Dashboard$Gate$explainOverall$);
var $author$project$Mario$Dashboard$Format$fraction$ = function (numerator, denominator) {
	return $author$project$Mario$Dashboard$Format$count(numerator) + (' / ' + $author$project$Mario$Dashboard$Format$count(denominator));
};
var $author$project$Mario$Dashboard$Format$fraction = F2($author$project$Mario$Dashboard$Format$fraction$);
var $author$project$Mario$Dashboard$gateLegend$ = function (scoring, target) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('gate-legend')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#4fd6e0')
							]),
						_List_Nil),
						$elm$html$Html$text('Wilson lower bound')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', 'rgba(79,214,224,0.3)')
							]),
						_List_Nil),
						$elm$html$Html$text(
						'raw ' + $author$project$Mario$Dashboard$Scoring$rateLabel(scoring))
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#f4ead6')
							]),
						_List_Nil),
						$elm$html$Html$text(
						'gate target ' + $author$project$Mario$Dashboard$Format$percent(target))
					]))
			]));
};
var $author$project$Mario$Dashboard$gateLegend = F2($author$project$Mario$Dashboard$gateLegend$);
var $author$project$Mario$Dashboard$gateMeter$ = function (target, verdict, rateFraction, boundFraction) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('gate-meter')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('gate-meter-rate'),
						A2(
						$elm$html$Html$Attributes$style,
						'width',
						$author$project$Mario$Dashboard$Format$decimal$(
							2,
							$elm$core$Basics$clamp$(0, 1, rateFraction) * 100) + '%')
					]),
				_List_Nil),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class(
						'gate-meter-bound' + function () {
							if (verdict.$ === 2) {
								return '';
							} else {
								return ' is-short';
							}
						}()),
						A2(
						$elm$html$Html$Attributes$style,
						'width',
						$author$project$Mario$Dashboard$Format$decimal$(
							2,
							$elm$core$Basics$clamp$(0, 1, boundFraction) * 100) + '%')
					]),
				_List_Nil),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('gate-meter-target'),
						A2(
						$elm$html$Html$Attributes$style,
						'left',
						$author$project$Mario$Dashboard$Format$decimal$(
							2,
							$elm$core$Basics$clamp$(0, 1, target) * 100) + '%')
					]),
				_List_Nil)
			]));
};
var $author$project$Mario$Dashboard$gateMeter = F4($author$project$Mario$Dashboard$gateMeter$);
var $author$project$Mario$Dashboard$gateStandingLine$ = function (model, overall) {
	if ($author$project$Mario$Dashboard$isStale(model)) {
		return 'These figures are from a stale snapshot; see the notice above.';
	} else {
		if (overall.gB) {
			return 'Both rounds have cleared the overall target for this champion. That is an aggregate result over the balanced distribution, not a per-matchup guarantee; the per-hull table below shows where it is weakest.';
		} else {
			var _v0 = _Utils_Tuple2(overall.kS, overall.dF);
			if (!_v0.a.$) {
				var cleared = _v0.a.a;
				var current = _v0.b;
				return (!_Utils_eq(
					$elm$core$Maybe$Just(cleared),
					current)) ? ('Champion ' + ($author$project$Mario$Dashboard$Format$shortId(cleared) + ' cleared both rounds, but it is no longer the champion. That result belongs to that policy and is not inherited, so the gate stands open again.')) : 'Passes only after the audit round and then an independent confirm round. Neither round\'s evidence is added to the other\'s.';
			} else {
				var _v1 = _v0.a;
				return 'Passes only after the audit round and then an independent confirm round. Neither round\'s evidence is added to the other\'s.';
			}
		}
	}
};
var $author$project$Mario$Dashboard$gateStandingLine = F2($author$project$Mario$Dashboard$gateStandingLine$);
var $elm$core$Basics$ge = _Utils_ge;
var $elm$core$Basics$sqrt = _Basics_sqrt;
var $author$project$Mario$Dashboard$Gate$wilsonLower$ = function (z, wins, games) {
	if (games <= 0) {
		return $elm$core$Maybe$Nothing;
	} else {
		var zz = z * z;
		var n = games;
		var p = wins / n;
		var margin = z * $elm$core$Basics$sqrt(((p * (1 - p)) + (zz / (4 * n))) / n);
		var denominator = 1 + (zz / n);
		var centre = p + (zz / (2 * n));
		return $elm$core$Maybe$Just(
			$elm$core$Basics$clamp$(0, p, (centre - margin) / denominator));
	}
};
var $author$project$Mario$Dashboard$Gate$wilsonLower = F3($author$project$Mario$Dashboard$Gate$wilsonLower$);
var $author$project$Mario$Dashboard$Gate$winsNeeded$ = function (z, target, games) {
	return (games <= 0) ? $elm$core$Maybe$Nothing : $elm$core$List$head(
		$elm$core$List$filter$(
			function (wins) {
				var _v0 = $author$project$Mario$Dashboard$Gate$wilsonLower$(z, wins, games);
				if (!_v0.$) {
					var bound = _v0.a;
					return _Utils_cmp(bound, target) > -1;
				} else {
					return false;
				}
			},
			$elm$core$List$range$(0, games)));
};
var $author$project$Mario$Dashboard$Gate$winsNeeded = F3($author$project$Mario$Dashboard$Gate$winsNeeded$);
var $author$project$Mario$Dashboard$Gate$z95 = 1.96;
var $author$project$Mario$Dashboard$overallDemandLine$ = function (scoring, overall) {
	var _v0 = $author$project$Mario$Dashboard$Gate$winsNeeded$($author$project$Mario$Dashboard$Gate$z95, overall.aJ, overall.cJ);
	if (!_v0.$) {
		var wins = _v0.a;
		return 'On the balanced panel of ' + ($elm$core$String$fromInt(overall.cJ) + (' games, clearing the ' + ($author$project$Mario$Dashboard$Format$percent(overall.aJ) + (' Wilson lower bound takes ' + ($elm$core$String$fromInt(wins) + (' observed ' + ($author$project$Mario$Dashboard$Scoring$successPlural(scoring) + (' (' + ($author$project$Mario$Dashboard$Format$percent1(wins / overall.cJ) + ('), not ' + ($elm$core$String$fromInt(
			$elm$core$Basics$ceiling(overall.aJ * overall.cJ)) + '. The same has to happen twice, on two independent rounds.')))))))))));
	} else {
		return 'No overall panel size has been published yet, so the observed count the gate demands cannot be stated.';
	}
};
var $author$project$Mario$Dashboard$overallDemandLine = F2($author$project$Mario$Dashboard$overallDemandLine$);
var $author$project$Mario$Dashboard$Copy$rateOf = $author$project$Mario$Dashboard$Scoring$rateLabel;
var $author$project$Mario$Dashboard$Copy$overallGate = function (scoring) {
	return A4(
		$author$project$Mario$Dashboard$Copy$t,
		'overall-gate',
		'Overall balanced ' + $author$project$Mario$Dashboard$Copy$rateOf(scoring),
		'The frozen champion\'s ' + ($author$project$Mario$Dashboard$Copy$rateOf(scoring) + ' on a fixed held-out balanced panel: all 25 of our hulls and all 25 opponent hulls equally represented, pairings randomised, every pair played in both seats. The gate is a floor on the Wilson lower bound, cleared on an audit round and then again on an independent confirm round. Because each pair is played in both seats the outcomes are correlated, so this is an operational confidence check on the distribution, not a formal guarantee about every matchup.'),
		_List_fromArray(
			[
				_Utils_Tuple2(
				'Denominator',
				function () {
					var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
					if (_v0.$ === 1) {
						return 'Games on the current round\'s balanced held-out panel. All games count, including unresolved ones, which are scored on crew share like any other.';
					} else {
						return 'Games on the current round\'s balanced held-out panel. All games count, including timeouts, which count as non-wins.';
					}
				}()),
				_Utils_Tuple2('Window', 'One round, one frozen champion. Rounds are never added together.'),
				_Utils_Tuple2('Source', 'Held-out gate evidence. Not training play, and not the readiness probe.')
			]));
};
var $author$project$Mario$Dashboard$Copy$overallPanel = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'overall-panel',
	'Balanced held-out panel',
	'The predeclared size of each gate round, built as pairs played in both seats so neither seat can be over-represented. The panel does not enumerate all 625 ordered matchups; it draws a balanced sample in which every hull appears equally often on each side.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Games per round, and the pair count behind them.'),
			_Utils_Tuple2('Window', 'Per round; the audit and confirm rounds each get their own panel and their own trial counter.'),
			_Utils_Tuple2('Source', 'Predeclared before the round opens, never resized mid-attempt.')
		]));
var $author$project$Mario$Dashboard$Copy$overallRound = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'overall-round',
	'Gate round',
	'Which of the two rounds is in flight. The audit round comes first; clearing it is provisional. The same frozen champion then has to clear an independent confirm round on a separate panel with its own trial counter before the gate is passed. A round can be abandoned early once the target has become arithmetically unreachable.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a phase.'),
			_Utils_Tuple2('Window', 'The current attempt.'),
			_Utils_Tuple2('Source', 'The trainer\'s declared round.')
		]));
var $author$project$Mario$Dashboard$Api$overallRoundLabel = function (round) {
	switch (round.$) {
		case 0:
			return 'audit';
		case 1:
			return 'confirm';
		default:
			var other = round.a;
			return other;
	}
};
var $author$project$Mario$Dashboard$Gate$NoEvidence = {$: 0};
var $author$project$Mario$Dashboard$Gate$Passing = function (a) {
	return {$: 2, a: a};
};
var $author$project$Mario$Dashboard$Gate$RateOnly = function (a) {
	return {$: 3, a: a};
};
var $author$project$Mario$Dashboard$Gate$Short = function (a) {
	return {$: 1, a: a};
};
var $author$project$Mario$Dashboard$Gate$overallVerdict = function (overall) {
	if (overall.ay <= 0) {
		return $author$project$Mario$Dashboard$Gate$NoEvidence;
	} else {
		var _v0 = overall.e5;
		if (!_v0.$) {
			var bound = _v0.a;
			return (_Utils_cmp(bound, overall.aJ) > -1) ? $author$project$Mario$Dashboard$Gate$Passing(bound) : $author$project$Mario$Dashboard$Gate$Short(bound);
		} else {
			var _v1 = overall.g3;
			if (!_v1.$) {
				var rate = _v1.a;
				return $author$project$Mario$Dashboard$Gate$RateOnly(rate);
			} else {
				return $author$project$Mario$Dashboard$Gate$NoEvidence;
			}
		}
	}
};
var $author$project$Mario$Dashboard$roundMetric$ = function (tips, tip, label, target, round) {
	return $author$project$Mario$Dashboard$viewMetric$(
		tips,
		{
			u: ((round.ay > 0) && round.gB) ? 'metric-cyan' : ((round.ay > 0) ? 'metric-amber' : ''),
			n: label,
			v: (round.ay > 0) ? ($author$project$Mario$Dashboard$Format$fraction$(round.fD, round.ay) + (' games, ' + (round.gB ? ('cleared ' + $author$project$Mario$Dashboard$Format$percent(target)) : 'not cleared'))) : 'not played on this attempt',
			w: tip,
			r: (round.ay > 0) ? $elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$percent1, round.e5) : $elm$core$Maybe$Nothing
		});
};
var $author$project$Mario$Dashboard$roundMetric = F5($author$project$Mario$Dashboard$roundMetric$);
var $author$project$Mario$Dashboard$Tip$AlignEnd = 1;
var $author$project$Mario$Dashboard$Copy$gateCriterion = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'gate-criterion',
	'Fitness is not the gate',
	'The scoring rule ranks the population for breeding. This gate decides whether the run is allowed to move on, and it is judged on fresh audit evidence which may measure something else entirely. A champion can be the best-scoring genome in the population and still fail this gate, and that is the point of keeping them apart.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'The gate\'s own predeclared panel of audit games.'),
			_Utils_Tuple2('Window', 'The current champion\'s audit panel only.'),
			_Utils_Tuple2('Source', 'Trainer scoring block, which names the gate criterion alongside the fitness.')
		]));
var $author$project$Mario$Dashboard$Api$fitnessLabel = function (fitness) {
	switch (fitness.$) {
		case 0:
			return 'combat';
		case 1:
			return 'crew ratio';
		default:
			var other = fitness.a;
			return $elm$core$String$isEmpty(other) ? 'not reported' : other;
	}
};
var $author$project$Mario$Dashboard$Api$gateCriterionLabel = function (criterion) {
	switch (criterion.$) {
		case 0:
			return 'actual combat wins';
		case 1:
			return 'strict crew-share leads';
		default:
			var other = criterion.a;
			return $elm$core$String$isEmpty(other) ? 'not reported' : other;
	}
};
var $author$project$Mario$Dashboard$Scoring$gateNote = function (scoring) {
	return $elm$core$Maybe$andThen$(
		function (reported) {
			var _v0 = _Utils_Tuple2(reported.kc, reported.eZ);
			if ((!_v0.a.$) && (!_v0.b.$)) {
				var _v1 = _v0.a;
				var _v2 = _v0.b;
				return $elm$core$Maybe$Nothing;
			} else {
				var fitness = _v0.a;
				var gate = _v0.b;
				return $elm$core$Maybe$Just(
					'Breeding ranks on ' + ($author$project$Mario$Dashboard$Api$fitnessLabel(fitness) + ('; this gate counts ' + ($author$project$Mario$Dashboard$Api$gateCriterionLabel(gate) + '.'))));
			}
		},
		scoring);
};
var $author$project$Mario$Dashboard$scoringNote$ = function (tips, status) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$gateNote(status.m);
	if (_v0.$ === 1) {
		return _List_Nil;
	} else {
		var note = _v0.a;
		return _List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel-note')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						1,
						$author$project$Mario$Dashboard$Copy$gateCriterion,
						_List_fromArray(
							[
								$elm$html$Html$text(note)
							]))
					]))
			]);
	}
};
var $author$project$Mario$Dashboard$scoringNote = F2($author$project$Mario$Dashboard$scoringNote$);
var $author$project$Mario$Dashboard$viewGate$ = function (tips, model, status) {
	var heading = 'Overall balanced ' + $author$project$Mario$Dashboard$Scoring$rateLabel(status.m);
	var gateTip = $author$project$Mario$Dashboard$Tip$detail$(
		$author$project$Mario$Dashboard$Copy$overallGate(status.m),
		_Utils_ap(
			$author$project$Mario$Dashboard$Gate$explainOverall$(status.m, status.fH, status.cd, status.fn),
			$author$project$Mario$Dashboard$Scoring$explainGate(status.m)));
	var _v0 = status.cd;
	if (_v0.$ === 1) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('panel')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('panel-head')
						]),
					_Utils_ap(
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$Tip$view$(
								tips,
								0,
								gateTip,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h2,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(heading)
											]))
									])),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('panel-note')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('any ship versus any ship, Awesome cyborgs')
									]))
							]),
						$author$project$Mario$Dashboard$scoringNote$(tips, status))),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('placeholder')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$strong,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text($author$project$Mario$Dashboard$Format$awaiting)
								])),
							A2(
							$elm$html$Html$span,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('The trainer has not published an overall balanced panel result yet. This is an absence of evidence, not a score of zero.')
								]))
						]))
				]));
	} else {
		var overall = _v0.a;
		var verdict = $author$project$Mario$Dashboard$Gate$overallVerdict(overall);
		var verdictLine = function () {
			switch (verdict.$) {
				case 0:
					return 'No games have been played on this round\'s balanced panel yet, so the overall gate cannot be judged. This is not a score of zero.';
				case 2:
					var bound = verdict.a;
					return 'Wilson lower bound ' + ($author$project$Mario$Dashboard$Format$percent1(bound) + (' clears the ' + ($author$project$Mario$Dashboard$Format$percent(overall.aJ) + ' overall target on this round\'s panel.')));
				case 1:
					var bound = verdict.a;
					return 'Wilson lower bound ' + ($author$project$Mario$Dashboard$Format$percent1(bound) + (' is below the ' + ($author$project$Mario$Dashboard$Format$percent(overall.aJ) + ' overall target, so this round does not support a pass.')));
				default:
					var rate = verdict.a;
					return 'The trainer published a raw rate of ' + ($author$project$Mario$Dashboard$Format$percent1(rate) + ' but no confidence bound, so the gate is undecided. It is judged on the bound.');
			}
		}();
		var roundText = function () {
			var _v5 = overall.gK;
			if (!_v5.$) {
				var round = _v5.a;
				return $author$project$Mario$Dashboard$Api$overallRoundLabel(round) + ' round in flight';
			} else {
				return 'no round in flight';
			}
		}();
		var _v1 = function () {
			var _v2 = overall.g3;
			if (!_v2.$) {
				var rate = _v2.a;
				return _Utils_Tuple2(
					function () {
						if (verdict.$ === 2) {
							return 'gate-rate gate-pass';
						} else {
							return 'gate-rate gate-fail';
						}
					}(),
					$author$project$Mario$Dashboard$Format$percent1(rate));
			} else {
				return _Utils_Tuple2('gate-rate is-unknown', $author$project$Mario$Dashboard$Format$awaiting);
			}
		}();
		var rateClass = _v1.a;
		var rateText = _v1.b;
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('panel')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('panel-head')
						]),
					_Utils_ap(
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$Tip$view$(
								tips,
								0,
								gateTip,
								_List_fromArray(
									[
										A2(
										$elm$html$Html$h2,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(heading)
											]))
									])),
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('panel-note')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('any ship versus any ship, Awesome cyborgs \u00B7 ' + roundText)
									]))
							]),
						$author$project$Mario$Dashboard$scoringNote$(tips, status))),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('gate')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('gate-figure')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class(rateClass)
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(rateText)
										])),
									A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('gate-denominator')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											(overall.ay > 0) ? ('over ' + ($author$project$Mario$Dashboard$Format$fraction$(overall.fD, overall.ay) + ' games on the balanced held-out panel')) : 'no games played on this round\'s panel yet')
										])),
									$author$project$Mario$Dashboard$gateMeter$(
									overall.aJ,
									verdict,
									$elm$core$Maybe$withDefault$(0, overall.g3),
									$elm$core$Maybe$withDefault$(0, overall.e5)),
									$author$project$Mario$Dashboard$gateLegend$(status.m, overall.aJ),
									A2(
									$elm$html$Html$p,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('prose')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(verdictLine)
										])),
									A2(
									$elm$html$Html$p,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('prose')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											'An aggregate over a balanced held-out panel, not a promise about every matchup. ' + $author$project$Mario$Dashboard$overallDemandLine$(status.m, overall))
										]))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('gate-side')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$div,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('metrics')
										]),
									_List_fromArray(
										[
											$author$project$Mario$Dashboard$viewMetric$(
											tips,
											{
												u: function () {
													switch (verdict.$) {
														case 2:
															return 'metric-cyan';
														case 1:
															return 'metric-amber';
														default:
															return '';
													}
												}(),
												n: 'Lower bound',
												v: 'overall target ' + $author$project$Mario$Dashboard$Format$percent(overall.aJ),
												w: $author$project$Mario$Dashboard$Copy$overallGate(status.m),
												r: $elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$percent1, overall.e5)
											}),
											$author$project$Mario$Dashboard$viewMetric$(
											tips,
											{
												u: '',
												n: 'Panel sample',
												v: $author$project$Mario$Dashboard$Scoring$successPlural(status.m) + (' over ' + ($elm$core$String$fromInt(overall.cJ) + (' predeclared games, ' + ($elm$core$String$fromInt(overall.kR) + ' pairs in both seats')))),
												w: $author$project$Mario$Dashboard$Copy$overallPanel,
												r: (overall.ay > 0) ? $elm$core$Maybe$Just(
													$author$project$Mario$Dashboard$Format$fraction$(overall.fD, overall.ay)) : $elm$core$Maybe$Nothing
											}),
											$author$project$Mario$Dashboard$viewMetric$(
											tips,
											{
												u: '',
												n: 'Round',
												v: 'attempt ' + ($elm$core$String$fromInt(overall.jF) + ', champion frozen throughout'),
												w: $author$project$Mario$Dashboard$Copy$overallRound,
												r: $elm$core$Maybe$map$($author$project$Mario$Dashboard$Api$overallRoundLabel, overall.gK)
											}),
											$author$project$Mario$Dashboard$viewMetric$(
											tips,
											{
												u: '',
												n: 'Champion',
												v: 'evidence resets when this changes',
												w: $author$project$Mario$Dashboard$Copy$championId,
												r: $elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$shortId, overall.dF)
											}),
											$author$project$Mario$Dashboard$roundMetric$(tips, $author$project$Mario$Dashboard$Copy$overallRound, 'Audit round', overall.aJ, overall.jG),
											$author$project$Mario$Dashboard$roundMetric$(tips, $author$project$Mario$Dashboard$Copy$overallRound, 'Confirm round', overall.aJ, overall.jV)
										])),
									A2(
									$elm$html$Html$p,
									_List_fromArray(
										[
											$elm$html$Html$Attributes$class('prose')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Mario$Dashboard$gateStandingLine$(model, overall))
										]))
								]))
						]))
				]));
	}
};
var $author$project$Mario$Dashboard$viewGate = F3($author$project$Mario$Dashboard$viewGate$);
var $author$project$Mario$Dashboard$HeatClear = {$: 15};
var $author$project$Mario$Dashboard$HeatSelect$ = function (a, b) {
	return {$: 14, a: a, b: b};
};
var $author$project$Mario$Dashboard$HeatSelect = F2($author$project$Mario$Dashboard$HeatSelect$);
var $elm$html$Html$details = _VirtualDom_node('details');
var $elm$html$Html$summary = _VirtualDom_node('summary');
var $author$project$Mario$Dashboard$foldPanel$ = function (tips, tip, title, note, children) {
	return A2(
		$elm$html$Html$details,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('panel panel-fold')
			]),
		A2(
			$elm$core$List$cons,
			A2(
				$elm$html$Html$summary,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel-head')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						tip,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(title)
									]))
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('panel-note')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(note)
							]))
					])),
			children));
};
var $author$project$Mario$Dashboard$foldPanel = F5($author$project$Mario$Dashboard$foldPanel$);
var $elm$core$List$member$ = function (x, xs) {
	return $elm$core$List$any$(
		function (a) {
			return _Utils_eq(a, x);
		},
		xs);
};
var $elm$core$List$member = F2($elm$core$List$member$);
var $author$project$Mario$Dashboard$Heatmap$grid = function (matchups) {
	var unique = function (list) {
		return $elm$core$List$foldl$(
			F2(
				function (x, acc) {
					return $elm$core$List$member$(x, acc) ? acc : _Utils_ap(
						acc,
						_List_fromArray(
							[x]));
				}),
			_List_Nil,
			list);
	};
	return {
		c$: $elm$core$List$foldl$(
			F2(
				function (m, acc) {
					return $elm$core$Dict$insert$(
						_Utils_Tuple2(m.lx, m.ln),
						m,
						acc);
				}),
			$elm$core$Dict$empty,
			matchups),
		b1: unique(
			$elm$core$List$map$(
				function ($) {
					return $.ln;
				},
				matchups)),
		ce: unique(
			$elm$core$List$map$(
				function ($) {
					return $.lx;
				},
				matchups))
	};
};
var $elm$html$Html$h3 = _VirtualDom_node('h3');
var $author$project$Mario$Dashboard$Copy$heatmap = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'heatmap',
	'Matchup training exposure',
	'One cell per ordered matchup: our ship in the row, the opponent in the column. Colour follows the sampler\'s own decayed training rate for that cell, and a cell with no training games is drawn as unmeasured rather than as zero, because never practised and always beaten are very different things. Nothing here is held-out evidence and no cell has a gate of its own; the aggregate target is drawn on the same scale only so the spread can be read against the one number the run is graded on.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Per cell, that cell\'s decayed training games. The count is fractional because older games decay rather than being dropped.'),
			_Utils_Tuple2('Window', 'Cumulative training play, decayed toward recent generations.'),
			_Utils_Tuple2('Source', 'The training sampler\'s own tallies. Not audit evidence, and it gates nothing.')
		]));
var $author$project$Mario$Dashboard$Api$opponentTypeLabel = function (kind) {
	switch (kind.$) {
		case 0:
			return 'cyborg';
		case 1:
			return 'frozen model';
		default:
			var other = kind.a;
			return other;
	}
};
var $elm$json$Json$Decode$fail = _Json_fail;
var $author$project$Mario$Dashboard$Heatmap$arrowDecoder$ = function (config, rows, cols) {
	return A2(
		$elm$json$Json$Decode$andThen,
		function (key) {
			var go = F2(
				function (dr, dc) {
					var _v1 = config.i4;
					if (_v1.$ === 1) {
						return $elm$json$Json$Decode$succeed(
							_Utils_Tuple2(
								A2(config.iI, 0, 0),
								true));
					} else {
						var _v2 = _v1.a;
						var r = _v2.a;
						var c = _v2.b;
						return $elm$json$Json$Decode$succeed(
							_Utils_Tuple2(
								A2(
									config.iI,
									$elm$core$Basics$max$(
										0,
										$elm$core$Basics$min$(rows - 1, r + dr)),
									$elm$core$Basics$max$(
										0,
										$elm$core$Basics$min$(cols - 1, c + dc))),
								true));
					}
				});
			switch (key) {
				case 'ArrowUp':
					return A2(go, -1, 0);
				case 'ArrowDown':
					return A2(go, 1, 0);
				case 'ArrowLeft':
					return A2(go, 0, -1);
				case 'ArrowRight':
					return A2(go, 0, 1);
				case 'Escape':
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(config.iH, false));
				default:
					return $elm$json$Json$Decode$fail('ignored');
			}
		},
		A2($elm$json$Json$Decode$field, 'key', $elm$json$Json$Decode$string));
};
var $author$project$Mario$Dashboard$Heatmap$arrowDecoder = F3($author$project$Mario$Dashboard$Heatmap$arrowDecoder$);
var $author$project$Mario$Dashboard$Heatmap$cellSize = function (columns) {
	return (columns <= 6) ? 34 : ((columns <= 12) ? 26 : ((columns <= 18) ? 20 : 15));
};
var $author$project$Mario$Dashboard$Heatmap$lerp$ = function (_v0, _v1, t) {
	var r1 = _v0.a;
	var g1 = _v0.b;
	var b1 = _v0.c;
	var r2 = _v1.a;
	var g2 = _v1.b;
	var b2 = _v1.c;
	var k = $elm$core$Basics$clamp$(0, 1, t);
	var mix = F2(
		function (a, b) {
			return $elm$core$String$fromInt(
				$elm$core$Basics$round(a + ((b - a) * k)));
		});
	return 'rgb(' + (A2(mix, r1, r2) + (',' + (A2(mix, g1, g2) + (',' + (A2(mix, b1, b2) + ')')))));
};
var $author$project$Mario$Dashboard$Heatmap$lerp = F3($author$project$Mario$Dashboard$Heatmap$lerp$);
var $author$project$Mario$Dashboard$Heatmap$cellFill$ = function (target, measured) {
	if (measured.$ === 1) {
		return '#131c30';
	} else {
		var v = measured.a;
		return (_Utils_cmp(v, target) > -1) ? $author$project$Mario$Dashboard$Heatmap$lerp$(
			_Utils_Tuple3(30, 106, 114),
			_Utils_Tuple3(79, 214, 224),
			(target >= 1) ? 1 : ((v - target) / (1 - target))) : $author$project$Mario$Dashboard$Heatmap$lerp$(
			_Utils_Tuple3(84, 28, 20),
			_Utils_Tuple3(255, 178, 63),
			(target <= 0) ? 1 : (v / target));
	}
};
var $author$project$Mario$Dashboard$Heatmap$cellFill = F2($author$project$Mario$Dashboard$Heatmap$cellFill$);
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
var $author$project$Mario$Dashboard$Heatmap$exposureStroke = function (games) {
	return (games > 0) ? '#24355c' : '#16203a';
};
var $elm$svg$Svg$Attributes$fill = _VirtualDom_attribute('fill');
var $elm$core$String$fromFloat = _String_fromNumber;
var $elm$svg$Svg$trustedNode = _VirtualDom_nodeNS('http://www.w3.org/2000/svg');
var $elm$svg$Svg$g = $elm$svg$Svg$trustedNode('g');
var $elm$svg$Svg$Attributes$height = _VirtualDom_attribute('height');
var $elm$svg$Svg$Events$onClick = function (msg) {
	return $elm$html$Html$Events$on$(
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$svg$Svg$Events$onMouseOver = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseover',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$svg$Svg$rect = $elm$svg$Svg$trustedNode('rect');
var $elm$svg$Svg$Attributes$rx = _VirtualDom_attribute('rx');
var $elm$svg$Svg$Attributes$stroke = _VirtualDom_attribute('stroke');
var $elm$svg$Svg$Attributes$strokeDasharray = _VirtualDom_attribute('stroke-dasharray');
var $elm$svg$Svg$Attributes$strokeWidth = _VirtualDom_attribute('stroke-width');
var $elm$svg$Svg$Attributes$width = _VirtualDom_attribute('width');
var $elm$svg$Svg$Attributes$x = _VirtualDom_attribute('x');
var $elm$svg$Svg$Attributes$y = _VirtualDom_attribute('y');
var $author$project$Mario$Dashboard$Heatmap$cellsSvg$ = function (config, g, size, gap, labelLeft, labelTop) {
	return $elm$core$List$concat(
		$elm$core$List$indexedMap$(
			F2(
				function (r, us) {
					return $elm$core$List$indexedMap$(
						F2(
							function (c, them) {
								var y = labelTop + (r * (size + gap));
								var x = labelLeft + (c * (size + gap));
								var isSelected = _Utils_eq(
									config.i4,
									$elm$core$Maybe$Just(
										_Utils_Tuple2(r, c)));
								var found = $elm$core$Dict$get$(
									_Utils_Tuple2(us, them),
									g.c$);
								var games = $elm$core$Maybe$withDefault$(
									0,
									$elm$core$Maybe$map$(
										function ($) {
											return $.lr;
										},
										found));
								var measured = $elm$core$Maybe$andThen$(
									function (m) {
										return (m.lr <= 0) ? $elm$core$Maybe$Nothing : m.ls;
									},
									found);
								return A2(
									$elm$svg$Svg$g,
									_List_Nil,
									_List_fromArray(
										[
											A2(
											$elm$svg$Svg$rect,
											_List_fromArray(
												[
													$elm$svg$Svg$Attributes$x(
													$elm$core$String$fromFloat(x)),
													$elm$svg$Svg$Attributes$y(
													$elm$core$String$fromFloat(y)),
													$elm$svg$Svg$Attributes$width(
													$elm$core$String$fromFloat(size)),
													$elm$svg$Svg$Attributes$height(
													$elm$core$String$fromFloat(size)),
													$elm$svg$Svg$Attributes$rx('3'),
													$elm$svg$Svg$Attributes$fill(
													$author$project$Mario$Dashboard$Heatmap$cellFill$(config.aJ, measured)),
													$elm$svg$Svg$Attributes$stroke(
													isSelected ? '#f4ead6' : $author$project$Mario$Dashboard$Heatmap$exposureStroke(games)),
													$elm$svg$Svg$Attributes$strokeWidth(
													isSelected ? '2' : '1'),
													$elm$svg$Svg$Attributes$strokeDasharray(
													_Utils_eq(measured, $elm$core$Maybe$Nothing) ? '2 2' : 'none'),
													$elm$svg$Svg$Events$onMouseOver(
													A2(config.iI, r, c)),
													$elm$svg$Svg$Events$onClick(
													A2(config.iI, r, c))
												]),
											_List_Nil)
										]));
							}),
						g.b1);
				}),
			g.ce));
};
var $author$project$Mario$Dashboard$Heatmap$cellsSvg = F6($author$project$Mario$Dashboard$Heatmap$cellsSvg$);
var $elm$svg$Svg$Attributes$class = _VirtualDom_attribute('class');
var $elm$svg$Svg$Attributes$fontFamily = _VirtualDom_attribute('font-family');
var $elm$svg$Svg$Attributes$fontSize = _VirtualDom_attribute('font-size');
var $author$project$Mario$Dashboard$Heatmap$shortName$ = function (columns, name) {
	return (columns <= 8) ? name : ((columns <= 16) ? $elm$core$String$left$(5, name) : $elm$core$String$left$(3, name));
};
var $author$project$Mario$Dashboard$Heatmap$shortName = F2($author$project$Mario$Dashboard$Heatmap$shortName$);
var $elm$svg$Svg$text = $elm$virtual_dom$VirtualDom$text;
var $elm$svg$Svg$Attributes$textAnchor = _VirtualDom_attribute('text-anchor');
var $elm$svg$Svg$text_ = $elm$svg$Svg$trustedNode('text');
var $elm$svg$Svg$Attributes$transform = _VirtualDom_attribute('transform');
var $author$project$Mario$Dashboard$Heatmap$colHeadings$ = function (g, size, gap, labelLeft, labelTop, cols) {
	return $elm$core$List$indexedMap$(
		F2(
			function (i, name) {
				var x = (labelLeft + (i * (size + gap))) + (size / 2);
				return A2(
					$elm$svg$Svg$text_,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat(x)),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat(labelTop - 6)),
							$elm$svg$Svg$Attributes$fontSize('9.5'),
							$elm$svg$Svg$Attributes$fill('#98a6c7'),
							$elm$svg$Svg$Attributes$textAnchor('start'),
							$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif'),
							$elm$svg$Svg$Attributes$transform(
							'rotate(-60 ' + ($elm$core$String$fromFloat(x) + (' ' + ($elm$core$String$fromFloat(labelTop - 6) + ')'))))
						]),
					_List_fromArray(
						[
							$elm$svg$Svg$text(
							$author$project$Mario$Dashboard$Heatmap$shortName$(cols, name))
						]));
			}),
		g.b1);
};
var $author$project$Mario$Dashboard$Heatmap$colHeadings = F6($author$project$Mario$Dashboard$Heatmap$colHeadings$);
var $elm$virtual_dom$VirtualDom$MayPreventDefault = function (a) {
	return {$: 2, a: a};
};
var $elm$html$Html$Events$preventDefaultOn$ = function (event, decoder) {
	return A2(
		$elm$virtual_dom$VirtualDom$on,
		event,
		$elm$virtual_dom$VirtualDom$MayPreventDefault(decoder));
};
var $elm$html$Html$Events$preventDefaultOn = F2($elm$html$Html$Events$preventDefaultOn$);
var $author$project$Mario$Dashboard$Heatmap$rowHeadings$ = function (g, size, gap, labelLeft, labelTop, cols) {
	return $elm$core$List$indexedMap$(
		F2(
			function (i, name) {
				return A2(
					$elm$svg$Svg$text_,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat(labelLeft - 8)),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat(((labelTop + (i * (size + gap))) + (size / 2)) + 3.5)),
							$elm$svg$Svg$Attributes$fontSize('9.5'),
							$elm$svg$Svg$Attributes$fill('#98a6c7'),
							$elm$svg$Svg$Attributes$textAnchor('end'),
							$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
						]),
					_List_fromArray(
						[
							$elm$svg$Svg$text(
							$author$project$Mario$Dashboard$Heatmap$shortName$(cols, name))
						]));
			}),
		g.ce);
};
var $author$project$Mario$Dashboard$Heatmap$rowHeadings = F6($author$project$Mario$Dashboard$Heatmap$rowHeadings$);
var $elm$svg$Svg$svg = $elm$svg$Svg$trustedNode('svg');
var $elm$svg$Svg$Attributes$viewBox = _VirtualDom_attribute('viewBox');
var $author$project$Mario$Dashboard$Heatmap$viewLegend = function (config) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('heat-legend')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#131c30')
							]),
						_List_Nil),
						$elm$html$Html$text('unmeasured (no training games)')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2(
								$elm$html$Html$Attributes$style,
								'background',
								$author$project$Mario$Dashboard$Heatmap$cellFill$(
									config.aJ,
									$elm$core$Maybe$Just(0)))
							]),
						_List_Nil),
						$elm$html$Html$text('0%')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2(
								$elm$html$Html$Attributes$style,
								'background',
								$author$project$Mario$Dashboard$Heatmap$cellFill$(
									config.aJ,
									$elm$core$Maybe$Just(config.aJ * 0.99)))
							]),
						_List_Nil),
						$elm$html$Html$text(
						'just under ' + $author$project$Mario$Dashboard$Format$percent(config.aJ))
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2(
								$elm$html$Html$Attributes$style,
								'background',
								$author$project$Mario$Dashboard$Heatmap$cellFill$(
									config.aJ,
									$elm$core$Maybe$Just(config.aJ)))
							]),
						_List_Nil),
						$elm$html$Html$text(
						'at ' + ($author$project$Mario$Dashboard$Format$percent(config.aJ) + ' (aggregate target)'))
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2(
								$elm$html$Html$Attributes$style,
								'background',
								$author$project$Mario$Dashboard$Heatmap$cellFill$(
									config.aJ,
									$elm$core$Maybe$Just(1)))
							]),
						_List_Nil),
						$elm$html$Html$text('100%')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text('Colour follows the decayed training rate. The target is the aggregate the run is graded on, drawn here only so the distribution can be read against it; no cell is judged on its own.')
					]))
			]));
};
var $author$project$Mario$Dashboard$Heatmap$viewReadout$ = function (config, g) {
	var wrap = function (children) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('heat-readout'),
					$elm$html$Html$Attributes$id(config.dM)
				]),
			children);
	};
	var at = F2(
		function (index, list) {
			return $elm$core$List$head(
				$elm$core$List$drop$(index, list));
		});
	var _v0 = config.i4;
	if (_v0.$ === 1) {
		return wrap(
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('ro-line')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Hover, tap, or focus the grid and use the arrow keys to read a cell\'s training exposure.')
						]))
				]));
	} else {
		var _v1 = _v0.a;
		var r = _v1.a;
		var c = _v1.b;
		var _v2 = _Utils_Tuple2(
			A2(at, r, g.ce),
			A2(at, c, g.b1));
		if ((!_v2.a.$) && (!_v2.b.$)) {
			var us = _v2.a.a;
			var them = _v2.b.a;
			var _v3 = $elm$core$Dict$get$(
				_Utils_Tuple2(us, them),
				g.c$);
			if (!_v3.$) {
				var m = _v3.a;
				return wrap(
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('ro-title')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									'our ' + (us + ('  vs  their ' + (them + ('  (' + ($author$project$Mario$Dashboard$Api$opponentTypeLabel(m.gx) + ')'))))))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('ro-line')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									(m.lr <= 0) ? 'No training games played for this ordered pair yet. Unmeasured, not lost.' : ('Training ' + (config.ll + (' rate ' + ($elm$core$Maybe$withDefault$(
										$author$project$Mario$Dashboard$Format$awaiting,
										$elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$percent1, m.ls)) + ('  \u00B7  over ' + ($author$project$Mario$Dashboard$Format$decimal$(1, m.lr) + (' decayed games  \u00B7  aggregate target ' + ($author$project$Mario$Dashboard$Format$percent(config.aJ) + ' for reference only')))))))))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('ro-line')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									'Sample weight ' + ($author$project$Mario$Dashboard$Format$decimal$(3, m.fk) + ' (weights steer what the next panel plays, never the gate)'))
								]))
						]));
			} else {
				return wrap(
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('ro-title')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('our ' + (us + ('  vs  their ' + them)))
								])),
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('ro-line')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('The trainer published no row for this ordered pair.')
								]))
						]));
			}
		} else {
			return wrap(
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('ro-line')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Select a cell to read its evidence.')
							]))
					]));
		}
	}
};
var $author$project$Mario$Dashboard$Heatmap$viewReadout = F2($author$project$Mario$Dashboard$Heatmap$viewReadout$);
var $author$project$Mario$Dashboard$Heatmap$view$ = function (config, g) {
	var rows = $elm$core$List$length(g.ce);
	var cols = $elm$core$List$length(g.b1);
	if ((!cols) || (!rows)) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('placeholder')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$strong,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('No matchups reported')
						])),
					A2(
					$elm$html$Html$span,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text('The trainer has not published any ordered matchups yet.')
						]))
				]));
	} else {
		var size = $author$project$Mario$Dashboard$Heatmap$cellSize(cols);
		var labelTop = 60;
		var labelLeft = (cols <= 12) ? 82 : 56;
		var gap = 2;
		var height = (labelTop + (rows * (size + gap))) + 10;
		var width = (labelLeft + (cols * (size + gap))) + 10;
		return A2(
			$elm$html$Html$div,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('heat-wrap')
						]),
					_List_fromArray(
						[
							A2(
							$elm$svg$Svg$svg,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$class('heat-svg'),
									$elm$svg$Svg$Attributes$viewBox(
									'0 0 ' + ($elm$core$String$fromFloat(width) + (' ' + $elm$core$String$fromFloat(height)))),
									$elm$svg$Svg$Attributes$width(
									$elm$core$String$fromFloat(width)),
									A2($elm$html$Html$Attributes$attribute, 'role', 'group'),
									A2($elm$html$Html$Attributes$attribute, 'tabindex', '0'),
									A2(
									$elm$html$Html$Attributes$attribute,
									'aria-label',
									'Ordered matchup training exposure grid, ' + ($elm$core$String$fromInt(rows) + (' of our ships by ' + ($elm$core$String$fromInt(cols) + ' opponent ships. Focus this grid and use the arrow keys to read each cell.')))),
									A2($elm$html$Html$Attributes$attribute, 'aria-describedby', config.dM),
									$elm$html$Html$Events$preventDefaultOn$(
									'keydown',
									$author$project$Mario$Dashboard$Heatmap$arrowDecoder$(config, rows, cols))
								]),
							_Utils_ap(
								$author$project$Mario$Dashboard$Heatmap$colHeadings$(g, size, gap, labelLeft, labelTop, cols),
								_Utils_ap(
									$author$project$Mario$Dashboard$Heatmap$rowHeadings$(g, size, gap, labelLeft, labelTop, cols),
									$author$project$Mario$Dashboard$Heatmap$cellsSvg$(config, g, size, gap, labelLeft, labelTop))))
						])),
					$author$project$Mario$Dashboard$Heatmap$viewReadout$(config, g),
					$author$project$Mario$Dashboard$Heatmap$viewLegend(config)
				]));
	}
};
var $author$project$Mario$Dashboard$Heatmap$view = F2($author$project$Mario$Dashboard$Heatmap$view$);
var $author$project$Mario$Dashboard$viewHeatmap$ = function (tips, model, status) {
	var target = $elm$core$Maybe$withDefault$(
		0.8,
		$elm$core$Maybe$map$(
			function ($) {
				return $.aJ;
			},
			status.cd));
	var renderGroup = function (_v2) {
		var kind = _v2.a;
		var list = _v2.b;
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$h3,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							'Opponent type: ' + $author$project$Mario$Dashboard$Api$opponentTypeLabel(kind))
						])),
					$author$project$Mario$Dashboard$Heatmap$view$(
					{
						dM: 'readout-heat',
						iH: $author$project$Mario$Dashboard$HeatClear,
						iI: $author$project$Mario$Dashboard$HeatSelect,
						i4: model.cw,
						ll: $author$project$Mario$Dashboard$Scoring$successPlural(status.m),
						aJ: target
					},
					$author$project$Mario$Dashboard$Heatmap$grid(list))
				]));
	};
	var others = $elm$core$List$filter$(
		function (m) {
			var _v1 = m.gx;
			if (_v1.$ === 2) {
				return true;
			} else {
				return false;
			}
		},
		status.dd);
	var byType = $elm$core$List$filter$(
		function (_v0) {
			var list = _v0.b;
			return !$elm$core$List$isEmpty(list);
		},
		$elm$core$List$map$(
			function (kind) {
				return _Utils_Tuple2(
					kind,
					$elm$core$List$filter$(
						function (m) {
							return _Utils_eq(m.gx, kind);
						},
						status.dd));
			},
			_List_fromArray(
				[$author$project$Mario$Dashboard$Api$Cyborg, $author$project$Mario$Dashboard$Api$ModelOpponent])));
	var groups = _Utils_ap(
		byType,
		$elm$core$List$isEmpty(others) ? _List_Nil : _List_fromArray(
			[
				_Utils_Tuple2(
				$author$project$Mario$Dashboard$Api$UnknownOpponent('other'),
				others)
			]));
	return $author$project$Mario$Dashboard$foldPanel$(
		tips,
		$author$project$Mario$Dashboard$Copy$heatmap,
		'Ordered matchup training exposure',
		$author$project$Mario$Dashboard$Format$count(
			$elm$core$List$length(status.dd)) + ' cells \u00B7 open to look closer',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('No cell has a gate of its own. This grid shows where the population has actually been made to practise and how those practice games went, which is what an aggregate cannot show. A cell with no games is unmeasured, not lost.')
					])),
				$elm$core$List$isEmpty(groups) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('placeholder')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('No matchups reported')
							])),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('The trainer has not published per-cell training exposure yet.')
							]))
					])) : A2(
				$elm$html$Html$div,
				_List_Nil,
				$elm$core$List$map$(renderGroup, groups))
			]));
};
var $author$project$Mario$Dashboard$viewHeatmap = F3($author$project$Mario$Dashboard$viewHeatmap$);
var $author$project$Mario$Dashboard$Resources$budgetLine = function (resources) {
	return ((resources.fE > 0) && (resources.eS > 0)) ? $elm$core$Maybe$Just(
		$author$project$Mario$Dashboard$Format$decimal$(1, resources.fE * resources.eS) + ' cores allowed, not measured load') : $elm$core$Maybe$Nothing;
};
var $author$project$Mario$Dashboard$Copy$checkpointGeneration = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'ckpt-generation',
	'Checkpointed generation',
	'The generation captured in the last checkpoint. If this lags the live generation, the work since then would be replayed deterministically on resume rather than lost.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count.'),
			_Utils_Tuple2('Window', 'Most recent save.'),
			_Utils_Tuple2('Source', 'Checkpoint writer.')
		]));
var $author$project$Mario$Dashboard$Copy$checkpointPath = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'ckpt-path',
	'Checkpoint path',
	'Where this run\'s immutable artifacts live. Every run gets its own directory, so re-running never overwrites earlier evidence.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a path.'),
			_Utils_Tuple2('Window', 'Fixed for the run.'),
			_Utils_Tuple2('Source', 'Run configuration.')
		]));
var $author$project$Mario$Dashboard$Copy$checkpointResumable = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'ckpt-resumable',
	'Resumable',
	'Whether the trainer can restart from the checkpoint and follow the same trajectory it would have followed uninterrupted. Evolution, sampling and evaluation each use their own generator, so scheduling differences cannot change outcomes.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a yes or no.'),
			_Utils_Tuple2('Window', 'Most recent save.'),
			_Utils_Tuple2('Source', 'Checkpoint validation.')
		]));
var $author$project$Mario$Dashboard$Copy$checkpointSaved = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'ckpt-saved',
	'Last checkpoint',
	'When the trainer last wrote a complete, atomic checkpoint. Checkpoints are written at completed batch and generation boundaries and capture the exact RNG state, genomes, species, innovations, curriculum, sampler statistics, pending work, frozen opponents and audit evidence.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; an instant.'),
			_Utils_Tuple2('Window', 'Most recent save.'),
			_Utils_Tuple2('Source', 'Checkpoint writer.')
		]));
var $author$project$Mario$Dashboard$Format$duration = function (seconds) {
	var total = $elm$core$Basics$max$(
		0,
		$elm$core$Basics$floor(seconds));
	var secs = A2($elm$core$Basics$modBy, 60, total);
	var pad = function (n) {
		return $elm$core$String$padLeft$(
			2,
			'0',
			$elm$core$String$fromInt(n));
	};
	var minutes = A2($elm$core$Basics$modBy, 60, (total / 60) | 0);
	var hours = A2($elm$core$Basics$modBy, 24, (total / 3600) | 0);
	var days = (total / 86400) | 0;
	return (days > 0) ? ($elm$core$String$fromInt(days) + ('d ' + (pad(hours) + (':' + (pad(minutes) + (':' + pad(secs))))))) : ((hours > 0) ? ($elm$core$String$fromInt(hours) + (':' + (pad(minutes) + (':' + pad(secs))))) : (pad(minutes) + (':' + pad(secs))));
};
var $author$project$Mario$Dashboard$Resources$dutyLine = function (resources) {
	var measured = function () {
		var _v1 = resources.e6;
		if (!_v1.$) {
			var value = _v1.a;
			return ', ' + ($author$project$Mario$Dashboard$Format$percent1(value) + ' measured working');
		} else {
			return ', not yet measured';
		}
	}();
	if (resources.eS > 0) {
		return $author$project$Mario$Dashboard$Format$percent1(resources.eS) + (' cap' + measured);
	} else {
		var _v0 = resources.e6;
		if (!_v0.$) {
			var value = _v0.a;
			return $author$project$Mario$Dashboard$Format$percent1(value) + ' measured working, no cap reported';
		} else {
			return 'not measured';
		}
	}
};
var $author$project$Mario$Dashboard$Copy$resourcesBudget = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'res-budget',
	'Compute budget',
	'The threads the pool runs multiplied by the duty cap: the share of the machine this run is allowed to occupy, stated in cores. It is a ceiling the scheduler is built to respect and never a measurement of load. What the run actually draws is measured outside the trainer, and an unbalanced batch or a serial stretch will draw less than the budget while the duty cycle still reads full.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Cores; threads multiplied by the duty cap.'),
			_Utils_Tuple2('Window', 'Current pool and configuration.'),
			_Utils_Tuple2('Source', 'Pool size and configured cap. Not a CPU measurement.')
		]));
var $author$project$Mario$Dashboard$Copy$resourcesDuty = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'res-duty',
	'Duty cycle',
	'The fraction of wall time the scheduler spends working rather than resting, enforced by real sleeps between batches rather than a busy wait. It is a scheduling figure, not a CPU measurement: an unbalanced batch can be wall-active the whole time with only one thread of the pool busy, so a full duty cycle never by itself means the threads beside it are full. The measurement accumulates over the whole run rather than over recent batches, so a run resumed under a raised cap reads below that cap until the new history outweighs the hours recorded under the old one. The cores line states the configured budget, threads multiplied by the cap, which is the capacity the run may use and not the load it is measured to draw.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Wall time working over working plus resting, accumulated since the run began.'),
			_Utils_Tuple2('Window', 'Accumulated run history, including earlier sessions and earlier resource settings.'),
			_Utils_Tuple2('Source', 'Evaluator scheduling, measured rather than assumed. Actual CPU load is measured outside the trainer.')
		]));
var $author$project$Mario$Dashboard$Copy$resourcesWorkers = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'res-workers',
	'Evaluator threads',
	'How many evaluator threads the pool actually runs, not how many were asked for. One is the legacy single-threaded trainer. More than one means independent fights and networks are evaluated side by side; the work is still planned and reduced in the one serial order, so the count changes how fast a generation finishes and never what it finds.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count of live pool threads.'),
			_Utils_Tuple2('Window', 'Current pool.'),
			_Utils_Tuple2('Source', 'The running pool, reported rather than configured.')
		]));
var $author$project$Mario$Dashboard$Copy$runId = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'run-id',
	'Run identifier',
	'The immutable identity of this training run. Every artifact, checkpoint and audit record for the run lives under this id. A different id means a different run with its own evidence; nothing is carried across.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None.'),
			_Utils_Tuple2('Window', 'Fixed for the lifetime of the run.'),
			_Utils_Tuple2('Source', 'Run directory under artifacts/mario.')
		]));
var $author$project$Mario$Dashboard$Resources$threadsLine = function (resources) {
	return (resources.fE <= 0) ? 'not reported' : ((resources.fE === 1) ? '1, evaluated inline' : ($elm$core$String$fromInt(resources.fE) + ' in the evaluator pool'));
};
var $author$project$Mario$Dashboard$viewMachine$ = function (tips, status) {
	var resources = status.gJ;
	var checkpoint = status.jQ;
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$resourcesWorkers,
		'Machine and checkpoint',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$dl,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('deflist')
					]),
				_Utils_ap(
					_List_fromArray(
						[
							A2(
							$elm$html$Html$dt,
							_List_Nil,
							_List_fromArray(
								[
									$author$project$Mario$Dashboard$Tip$view$(
									tips,
									0,
									$author$project$Mario$Dashboard$Copy$resourcesWorkers,
									_List_fromArray(
										[
											$elm$html$Html$text('Threads')
										]))
								])),
							A2(
							$elm$html$Html$dd,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									$author$project$Mario$Dashboard$Resources$threadsLine(resources))
								])),
							A2(
							$elm$html$Html$dt,
							_List_Nil,
							_List_fromArray(
								[
									$author$project$Mario$Dashboard$Tip$view$(
									tips,
									0,
									$author$project$Mario$Dashboard$Copy$resourcesDuty,
									_List_fromArray(
										[
											$elm$html$Html$text('Duty cycle')
										]))
								])),
							A2(
							$elm$html$Html$dd,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									$author$project$Mario$Dashboard$Resources$dutyLine(resources))
								]))
						]),
					_Utils_ap(
						function () {
							var _v0 = $author$project$Mario$Dashboard$Resources$budgetLine(resources);
							if (!_v0.$) {
								var budget = _v0.a;
								return _List_fromArray(
									[
										A2(
										$elm$html$Html$dt,
										_List_Nil,
										_List_fromArray(
											[
												$author$project$Mario$Dashboard$Tip$view$(
												tips,
												0,
												$author$project$Mario$Dashboard$Copy$resourcesBudget,
												_List_fromArray(
													[
														$elm$html$Html$text('Compute budget')
													]))
											])),
										A2(
										$elm$html$Html$dd,
										_List_Nil,
										_List_fromArray(
											[
												$elm$html$Html$text(budget)
											]))
									]);
							} else {
								return _List_Nil;
							}
						}(),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$resourcesBudget,
										_List_fromArray(
											[
												$elm$html$Html$text('Compute spent')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Mario$Dashboard$Format$duration(resources.jU) + ' of wall time actually computing, whole run')
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$resourcesWorkers,
										_List_fromArray(
											[
												$elm$html$Html$text('Nice')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$String$fromInt(resources.kC) + ', this invocation only')
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$checkpointSaved,
										_List_fromArray(
											[
												$elm$html$Html$text('Saved')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$Maybe$withDefault$('never in this run', checkpoint.k7))
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$checkpointGeneration,
										_List_fromArray(
											[
												$elm$html$Html$text('On disk')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Mario$Dashboard$Format$count(checkpoint.f3) + ', the generation a resume would start from')
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$checkpointResumable,
										_List_fromArray(
											[
												$elm$html$Html$text('Resumable')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										checkpoint.k2 ? 'yes, exact resume' : 'no')
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$checkpointPath,
										_List_fromArray(
											[
												$elm$html$Html$text('Path')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$elm$core$String$isEmpty(checkpoint.iK) ? 'not reported' : checkpoint.iK)
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$author$project$Mario$Dashboard$Tip$view$(
										tips,
										0,
										$author$project$Mario$Dashboard$Copy$runId,
										_List_fromArray(
											[
												$elm$html$Html$text('Run')
											]))
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(status.i1)
									]))
							]))))
			]));
};
var $author$project$Mario$Dashboard$viewMachine = F2($author$project$Mario$Dashboard$viewMachine$);
var $elm$core$Char$toUpper = _Char_toUpper;
var $author$project$Mario$Dashboard$Format$capitalise = function (text) {
	var _v0 = $elm$core$String$uncons(text);
	if (!_v0.$) {
		var _v1 = _v0.a;
		var first = _v1.a;
		var rest = _v1.b;
		return A2(
			$elm$core$String$cons,
			$elm$core$Char$toUpper(first),
			rest);
	} else {
		return text;
	}
};
var $author$project$Mario$Dashboard$Copy$nextGate = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'next-gate',
	'What opens the next gate',
	'The sequence a champion has to walk to clear the gate, in order: pass the cheap readiness probe, then post the demanded count on a full audit panel, then post it again on an independent confirm panel. Stating only the target percentage hides the first and third steps, and hides that the demanded count is higher than the target because the bound has to clear it rather than the raw rate.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'The readiness sample for the probe; the predeclared panel size for each round.'),
			_Utils_Tuple2('Window', 'The attempt in flight, or the next one if none is.'),
			_Utils_Tuple2('Source', 'Trainer configuration and the published round state.')
		]));
var $author$project$Mario$Dashboard$Gate$nextGateSteps$ = function (scoring, readiness, maybeOverall) {
	var successes = $author$project$Mario$Dashboard$Scoring$successPlural(scoring);
	var roundsLine = function (overall) {
		var _v3 = overall.gK;
		_v3$2:
		while (true) {
			if (!_v3.$) {
				switch (_v3.a.$) {
					case 0:
						var _v4 = _v3.a;
						return 'The audit round is in flight. Clearing it opens the confirm round, which has to post the same count again on its own panel and its own seeds.';
					case 1:
						var _v5 = _v3.a;
						return 'The confirm round is in flight. It is the last step: clearing it clears the gate for this champion.';
					default:
						break _v3$2;
				}
			} else {
				break _v3$2;
			}
		}
		return 'Nothing is in flight. The next probe that clears the threshold starts an audit round, and this would be attempt ' + ($elm$core$String$fromInt(overall.jF + 1) + '.');
	};
	var probeLine = function () {
		var _v2 = readiness.h0;
		if (!_v2.$) {
			var rate = _v2.a;
			return 'The last readiness probe scored ' + ($author$project$Mario$Dashboard$Format$percent1(rate) + ', ');
		} else {
			return 'No readiness probe has been scored yet, ';
		}
	}() + ('against a ' + ($author$project$Mario$Dashboard$Format$percent(readiness.je) + (' threshold over ' + ($elm$core$String$fromInt(readiness.ay) + (' balanced games' + ((readiness.iL > 0) ? (', run every ' + ($elm$core$String$fromInt(readiness.iL) + ' generations.')) : '.'))))));
	var demandLine = function (overall) {
		var _v1 = $author$project$Mario$Dashboard$Gate$winsNeeded$($author$project$Mario$Dashboard$Gate$z95, overall.aJ, overall.cJ);
		if (!_v1.$) {
			var wins = _v1.a;
			return 'An audit panel is ' + ($elm$core$String$fromInt(overall.cJ) + (' games, and clearing the ' + ($author$project$Mario$Dashboard$Format$percent(overall.aJ) + (' Wilson lower bound on it takes ' + ($elm$core$String$fromInt(wins) + (' observed ' + (successes + (' (' + ($author$project$Mario$Dashboard$Format$percent1(wins / overall.cJ) + ('), not ' + ($elm$core$String$fromInt(
				$elm$core$Basics$ceiling(overall.aJ * overall.cJ)) + '.')))))))))));
		} else {
			return 'No panel size has been published yet, so the observed count the gate demands cannot be stated.';
		}
	};
	if (maybeOverall.$ === 1) {
		return _List_fromArray(
			[probeLine, 'The trainer has published no balanced panel yet, so neither the panel size nor the count it demands is known.']);
	} else {
		var overall = maybeOverall.a;
		return _List_fromArray(
			[
				probeLine,
				demandLine(overall),
				roundsLine(overall)
			]);
	}
};
var $author$project$Mario$Dashboard$Gate$nextGateSteps = F3($author$project$Mario$Dashboard$Gate$nextGateSteps$);
var $author$project$Mario$Dashboard$Copy$successes = $author$project$Mario$Dashboard$Scoring$successPlural;
var $author$project$Mario$Dashboard$Copy$observedNeeded = function (scoring) {
	return A4(
		$author$project$Mario$Dashboard$Copy$t,
		'observed-needed',
		'Observed ' + ($author$project$Mario$Dashboard$Copy$successes(scoring) + ' the gate actually demands'),
		'The target is a floor on the Wilson lower bound, not on the observed rate, so the raw score a candidate must post is higher than the target. On a panel of 100 against an 80% target, 80 out of 100 fails: the bound on 80/100 is about 71%. It takes 88 counted ' + ($author$project$Mario$Dashboard$Copy$successes(scoring) + ' for the bound to clear 80%. Reading the target as though it were an observed rate is the single easiest way to believe a candidate passed when it did not.'),
		_List_fromArray(
			[
				_Utils_Tuple2('Denominator', 'The predeclared audit panel size.'),
				_Utils_Tuple2('Window', 'Per audit attempt.'),
				_Utils_Tuple2('Source', 'Computed by the dashboard as the inverse of the Wilson bound at 95% confidence, z = 1.96. The trainer publishes the bound itself; this is the smallest count that reaches it.')
			]));
};
var $author$project$Mario$Dashboard$Copy$readiness = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'readiness',
	'Readiness screen',
	'A cheap recurring check that decides when a candidate is worth spending an expensive audit panel on. It is a screening test, not gate evidence: passing it only buys the right to be audited, and its rate never counts toward a promotion.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Games in the readiness sample.'),
			_Utils_Tuple2('Window', 'Re-checked every few generations, as given by the period.'),
			_Utils_Tuple2('Source', 'Training-side screening. Never pooled with audit evidence.')
		]));
var $author$project$Mario$Dashboard$viewNextGate$ = function (tips, status) {
	var target = $elm$core$Maybe$withDefault$(
		0.8,
		$elm$core$Maybe$map$(
			function ($) {
				return $.aJ;
			},
			status.cd));
	var readiness = status.kZ;
	var panelSize = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$Maybe$map$(
			function ($) {
				return $.cJ;
			},
			status.cd));
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$nextGate,
		'What opens the next gate',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metrics')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: function () {
								var _v0 = readiness.h0;
								if (!_v0.$) {
									var rate = _v0.a;
									return (_Utils_cmp(rate, readiness.je) > -1) ? 'metric-cyan' : 'metric-amber';
								} else {
									return '';
								}
							}(),
							n: 'Readiness probe',
							v: 'needs ' + ($author$project$Mario$Dashboard$Format$percent(readiness.je) + (' over ' + ($elm$core$String$fromInt(readiness.ay) + (' balanced games to buy an audit' + ((readiness.iL > 0) ? (', probed every ' + ($elm$core$String$fromInt(readiness.iL) + ' generations')) : ''))))),
							w: $author$project$Mario$Dashboard$Copy$readiness,
							r: $elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$percent1, readiness.h0)
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: 'metric-amber',
							n: $author$project$Mario$Dashboard$Format$capitalise(
								$author$project$Mario$Dashboard$Scoring$successPlural(status.m)) + ' needed',
							v: 'observed, on one round\'s panel, to clear the bound',
							w: $author$project$Mario$Dashboard$Copy$observedNeeded(status.m),
							r: $elm$core$Maybe$map$(
								function (wins) {
									return $author$project$Mario$Dashboard$Format$fraction$(wins, panelSize);
								},
								$author$project$Mario$Dashboard$Gate$winsNeeded$($author$project$Mario$Dashboard$Gate$z95, target, panelSize))
						})
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
					]),
				$elm$core$List$map$(
					function (line) {
						return A2(
							$elm$html$Html$p,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('prose')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(line)
								]));
					},
					$author$project$Mario$Dashboard$Gate$nextGateSteps$(status.m, readiness, status.cd)))
			]));
};
var $author$project$Mario$Dashboard$viewNextGate = F2($author$project$Mario$Dashboard$viewNextGate$);
var $author$project$Mario$Dashboard$NodesHover = function (a) {
	return {$: 12, a: a};
};
var $author$project$Mario$Dashboard$NodesLeave = {$: 13};
var $author$project$Mario$Dashboard$chartPanel$ = function (tips, tip, title, status, body) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('panel')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel-head')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						tip,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(title)
									]))
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('panel-note')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								$elm$core$String$fromInt(
									$elm$core$List$length(status.c6)) + ' generations recorded')
							]))
					])),
				body
			]));
};
var $author$project$Mario$Dashboard$chartPanel = F5($author$project$Mario$Dashboard$chartPanel$);
var $author$project$Mario$Dashboard$countTicks = function (top) {
	var hi = $elm$core$Basics$max$(1, top);
	return $elm$core$List$map$(
		function (i) {
			var v = (hi * i) / 4;
			return _Utils_Tuple2(
				v,
				$author$project$Mario$Dashboard$Format$decimal$(0, v));
		},
		$elm$core$List$range$(0, 4));
};
var $author$project$Mario$Dashboard$Slots$controlCount = 5;
var $author$project$Mario$Dashboard$Slots$memoryChannels = 8;
var $author$project$Mario$Dashboard$Slots$outputCount = $author$project$Mario$Dashboard$Slots$controlCount + $author$project$Mario$Dashboard$Slots$memoryChannels;
var $author$project$Mario$Dashboard$Slots$sensorCount = 93;
var $author$project$Mario$Dashboard$Slots$shipBits = 5;
var $author$project$Mario$Dashboard$Slots$observationCount = $author$project$Mario$Dashboard$Slots$sensorCount + ($author$project$Mario$Dashboard$Slots$shipBits * 2);
var $author$project$Mario$Dashboard$Slots$biasIndex = ($author$project$Mario$Dashboard$Slots$observationCount + $author$project$Mario$Dashboard$Slots$controlCount) + $author$project$Mario$Dashboard$Slots$memoryChannels;
var $author$project$Mario$Dashboard$Slots$inputCount = $author$project$Mario$Dashboard$Slots$biasIndex + 1;
var $author$project$Mario$Dashboard$Slots$outputFirst = $author$project$Mario$Dashboard$Slots$inputCount;
var $author$project$Mario$Dashboard$Slots$hiddenFirst = $author$project$Mario$Dashboard$Slots$outputFirst + $author$project$Mario$Dashboard$Slots$outputCount;
var $author$project$Mario$Dashboard$historyLabels = function (status) {
	return $elm$core$List$map$(
		function (h) {
			return 'g' + $elm$core$String$fromInt(h.f3);
		},
		status.c6);
};
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
var $author$project$Mario$Dashboard$maxOf = function (values) {
	return $elm$core$Basics$max$(
		1,
		function (m) {
			return m * 1.15;
		}(
			$elm$core$Maybe$withDefault$(
				1,
				$elm$core$List$maximum(
					$elm$core$List$filterMap$($elm$core$Basics$identity, values)))));
};
var $author$project$Mario$Dashboard$Copy$nodesChart = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'chart-nodes',
	'Champion node count',
	'Nodes in the champion genome per generation. The first 130 are the fixed 117 inputs and 13 outputs and are present from the very first seeded genome; everything above that line is hidden structure this run actually discovered.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count per generation.'),
			_Utils_Tuple2('Window', 'Per generation, whole run.'),
			_Utils_Tuple2('Source', 'Champion genome census. Structure, not performance.')
		]));
var $author$project$Mario$Dashboard$Chart$series$ = function (key, label, color, values) {
	return {ht: color, c0: false, e2: key, n: label, kp: false, cV: values, jv: 2};
};
var $author$project$Mario$Dashboard$Chart$series = F4($author$project$Mario$Dashboard$Chart$series$);
var $author$project$Mario$Dashboard$Chart$ariaLabel$ = function (config, total) {
	return 'Trend chart, ' + ($elm$core$String$fromInt(total) + (' samples, series: ' + ($elm$core$String$join$(
		', ',
		$elm$core$List$map$(
			function ($) {
				return $.n;
			},
			config.gM)) + '. Focus this chart and use the left and right arrow keys to read each sample.')));
};
var $author$project$Mario$Dashboard$Chart$ariaLabel = F2($author$project$Mario$Dashboard$Chart$ariaLabel$);
var $author$project$Mario$Dashboard$Chart$clampIndex$ = function (total, index) {
	return $elm$core$Basics$max$(
		0,
		$elm$core$Basics$min$(total - 1, index));
};
var $author$project$Mario$Dashboard$Chart$clampIndex = F2($author$project$Mario$Dashboard$Chart$clampIndex$);
var $author$project$Mario$Dashboard$Chart$arrowDecoder$ = function (config, total) {
	return A2(
		$elm$json$Json$Decode$andThen,
		function (key) {
			var move = function (delta) {
				var _v1 = config.f9;
				if (_v1.$ === 1) {
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(
							config.gu(total - 1),
							true));
				} else {
					var current = _v1.a;
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(
							config.gu(
								$author$project$Mario$Dashboard$Chart$clampIndex$(total, current + delta)),
							true));
				}
			};
			switch (key) {
				case 'ArrowLeft':
					return move(-1);
				case 'ArrowRight':
					return move(1);
				case 'Home':
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(
							config.gu(0),
							true));
				case 'End':
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(
							config.gu(total - 1),
							true));
				case 'Escape':
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(config.gv, false));
				default:
					return $elm$json$Json$Decode$fail('ignored');
			}
		},
		A2($elm$json$Json$Decode$field, 'key', $elm$json$Json$Decode$string));
};
var $author$project$Mario$Dashboard$Chart$arrowDecoder = F2($author$project$Mario$Dashboard$Chart$arrowDecoder$);
var $elm$core$List$concatMap$ = function (f, list) {
	return $elm$core$List$concat(
		$elm$core$List$map$(f, list));
};
var $elm$core$List$concatMap = F2($elm$core$List$concatMap$);
var $elm$svg$Svg$Events$onMouseOut = function (msg) {
	return $elm$html$Html$Events$on$(
		'mouseout',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$svg$Svg$Attributes$preserveAspectRatio = _VirtualDom_attribute('preserveAspectRatio');
var $elm$svg$Svg$circle = $elm$svg$Svg$trustedNode('circle');
var $elm$svg$Svg$Attributes$cx = _VirtualDom_attribute('cx');
var $elm$svg$Svg$Attributes$cy = _VirtualDom_attribute('cy');
var $elm$svg$Svg$line = $elm$svg$Svg$trustedNode('line');
var $author$project$Mario$Dashboard$Chart$plotBottom = 26;
var $author$project$Mario$Dashboard$Chart$plotTop = 12;
var $elm$svg$Svg$Attributes$r = _VirtualDom_attribute('r');
var $author$project$Mario$Dashboard$Chart$sampleAt$ = function (index, values) {
	return $elm$core$Maybe$withDefault$(
		$elm$core$Maybe$Nothing,
		$elm$core$List$head(
			$elm$core$List$drop$(index, values)));
};
var $author$project$Mario$Dashboard$Chart$sampleAt = F2($author$project$Mario$Dashboard$Chart$sampleAt$);
var $author$project$Mario$Dashboard$Chart$plotLeft = 46;
var $author$project$Mario$Dashboard$Chart$plotRight = 10;
var $author$project$Mario$Dashboard$Chart$plotWidth = function (config) {
	return (config.g$ - $author$project$Mario$Dashboard$Chart$plotLeft) - $author$project$Mario$Dashboard$Chart$plotRight;
};
var $author$project$Mario$Dashboard$Chart$slotX$ = function (config, total, index) {
	return (total <= 1) ? ($author$project$Mario$Dashboard$Chart$plotLeft + ($author$project$Mario$Dashboard$Chart$plotWidth(config) / 2)) : ($author$project$Mario$Dashboard$Chart$plotLeft + (($author$project$Mario$Dashboard$Chart$plotWidth(config) * index) / (total - 1)));
};
var $author$project$Mario$Dashboard$Chart$slotX = F3($author$project$Mario$Dashboard$Chart$slotX$);
var $elm$svg$Svg$Attributes$strokeOpacity = _VirtualDom_attribute('stroke-opacity');
var $author$project$Mario$Dashboard$Chart$valueY$ = function (config, value) {
	var span_ = config.g7 - config.g8;
	var t = (span_ <= 0) ? 0.5 : ((value - config.g8) / span_);
	var plotHeight = (config.f8 - $author$project$Mario$Dashboard$Chart$plotTop) - $author$project$Mario$Dashboard$Chart$plotBottom;
	return $author$project$Mario$Dashboard$Chart$plotTop + (plotHeight * (1 - $elm$core$Basics$clamp$(0, 1, t)));
};
var $author$project$Mario$Dashboard$Chart$valueY = F2($author$project$Mario$Dashboard$Chart$valueY$);
var $elm$svg$Svg$Attributes$x1 = _VirtualDom_attribute('x1');
var $elm$svg$Svg$Attributes$x2 = _VirtualDom_attribute('x2');
var $elm$svg$Svg$Attributes$y1 = _VirtualDom_attribute('y1');
var $elm$svg$Svg$Attributes$y2 = _VirtualDom_attribute('y2');
var $author$project$Mario$Dashboard$Chart$viewCrosshair$ = function (config, total) {
	var _v0 = config.f9;
	if (_v0.$ === 1) {
		return _List_Nil;
	} else {
		var index = _v0.a;
		var x = $author$project$Mario$Dashboard$Chart$slotX$(
			config,
			total,
			$author$project$Mario$Dashboard$Chart$clampIndex$(total, index));
		return A2(
			$elm$core$List$cons,
			A2(
				$elm$svg$Svg$line,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$x1(
						$elm$core$String$fromFloat(x)),
						$elm$svg$Svg$Attributes$x2(
						$elm$core$String$fromFloat(x)),
						$elm$svg$Svg$Attributes$y1(
						$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotTop)),
						$elm$svg$Svg$Attributes$y2(
						$elm$core$String$fromFloat(config.f8 - $author$project$Mario$Dashboard$Chart$plotBottom)),
						$elm$svg$Svg$Attributes$stroke('#f4ead6'),
						$elm$svg$Svg$Attributes$strokeWidth('1'),
						$elm$svg$Svg$Attributes$strokeOpacity('0.5')
					]),
				_List_Nil),
			$elm$core$List$filterMap$(
				function (s) {
					return $elm$core$Maybe$map$(
						function (v) {
							return A2(
								$elm$svg$Svg$circle,
								_List_fromArray(
									[
										$elm$svg$Svg$Attributes$cx(
										$elm$core$String$fromFloat(x)),
										$elm$svg$Svg$Attributes$cy(
										$elm$core$String$fromFloat(
											$author$project$Mario$Dashboard$Chart$valueY$(config, v))),
										$elm$svg$Svg$Attributes$r('4'),
										$elm$svg$Svg$Attributes$fill('#05070f'),
										$elm$svg$Svg$Attributes$stroke(s.ht),
										$elm$svg$Svg$Attributes$strokeWidth('2')
									]),
								_List_Nil);
						},
						$author$project$Mario$Dashboard$Chart$sampleAt$(index, s.cV));
				},
				config.gM));
	}
};
var $author$project$Mario$Dashboard$Chart$viewCrosshair = F2($author$project$Mario$Dashboard$Chart$viewCrosshair$);
var $elm$core$Tuple$pair$ = function (a, b) {
	return _Utils_Tuple2(a, b);
};
var $elm$core$Tuple$pair = F2($elm$core$Tuple$pair$);
var $author$project$Mario$Dashboard$Chart$xAxisLabels$ = function (config, total) {
	var labels = $elm$core$List$indexedMap$($elm$core$Tuple$pair, config.g6);
	var keep = $elm$core$Basics$max$(
		1,
		$elm$core$Basics$ceiling(total / 8));
	return $elm$core$List$map$(
		function (_v1) {
			var i = _v1.a;
			var label = _v1.b;
			return A2(
				$elm$svg$Svg$text_,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$x(
						$elm$core$String$fromFloat(
							$author$project$Mario$Dashboard$Chart$slotX$(config, total, i))),
						$elm$svg$Svg$Attributes$y(
						$elm$core$String$fromFloat((config.f8 - $author$project$Mario$Dashboard$Chart$plotBottom) + 15)),
						$elm$svg$Svg$Attributes$textAnchor(
						(!i) ? 'start' : (_Utils_eq(i, total - 1) ? 'end' : 'middle')),
						$elm$svg$Svg$Attributes$fontSize('10'),
						$elm$svg$Svg$Attributes$fill('#7483a6'),
						$elm$svg$Svg$Attributes$fontFamily('ui-monospace, Menlo, Consolas, monospace')
					]),
				_List_fromArray(
					[
						$elm$svg$Svg$text(label)
					]));
		},
		$elm$core$List$filter$(
			function (_v0) {
				var i = _v0.a;
				return (!A2($elm$core$Basics$modBy, keep, i)) || _Utils_eq(i, total - 1);
			},
			labels));
};
var $author$project$Mario$Dashboard$Chart$xAxisLabels = F2($author$project$Mario$Dashboard$Chart$xAxisLabels$);
var $author$project$Mario$Dashboard$Chart$viewGrid$ = function (config, total) {
	var ticks = $elm$core$List$concatMap$(
		function (_v0) {
			var value = _v0.a;
			var label = _v0.b;
			var y = $author$project$Mario$Dashboard$Chart$valueY$(config, value);
			return _List_fromArray(
				[
					A2(
					$elm$svg$Svg$line,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x1(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotLeft)),
							$elm$svg$Svg$Attributes$x2(
							$elm$core$String$fromFloat(config.g$ - $author$project$Mario$Dashboard$Chart$plotRight)),
							$elm$svg$Svg$Attributes$y1(
							$elm$core$String$fromFloat(y)),
							$elm$svg$Svg$Attributes$y2(
							$elm$core$String$fromFloat(y)),
							$elm$svg$Svg$Attributes$stroke('#1a2540'),
							$elm$svg$Svg$Attributes$strokeWidth('1')
						]),
					_List_Nil),
					A2(
					$elm$svg$Svg$text_,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotLeft - 8)),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat(y + 3.5)),
							$elm$svg$Svg$Attributes$textAnchor('end'),
							$elm$svg$Svg$Attributes$fontSize('10'),
							$elm$svg$Svg$Attributes$fill('#7483a6'),
							$elm$svg$Svg$Attributes$fontFamily('ui-monospace, Menlo, Consolas, monospace')
						]),
					_List_fromArray(
						[
							$elm$svg$Svg$text(label)
						]))
				]);
		},
		config.g9);
	var bottomY = config.f8 - $author$project$Mario$Dashboard$Chart$plotBottom;
	return _Utils_ap(
		ticks,
		_Utils_ap(
			_List_fromArray(
				[
					A2(
					$elm$svg$Svg$line,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x1(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotLeft)),
							$elm$svg$Svg$Attributes$x2(
							$elm$core$String$fromFloat(config.g$ - $author$project$Mario$Dashboard$Chart$plotRight)),
							$elm$svg$Svg$Attributes$y1(
							$elm$core$String$fromFloat(bottomY)),
							$elm$svg$Svg$Attributes$y2(
							$elm$core$String$fromFloat(bottomY)),
							$elm$svg$Svg$Attributes$stroke('#24355c'),
							$elm$svg$Svg$Attributes$strokeWidth('1')
						]),
					_List_Nil)
				]),
			$author$project$Mario$Dashboard$Chart$xAxisLabels$(config, total)));
};
var $author$project$Mario$Dashboard$Chart$viewGrid = F2($author$project$Mario$Dashboard$Chart$viewGrid$);
var $author$project$Mario$Dashboard$Chart$viewGuides = function (config) {
	return $elm$core$List$concatMap$(
		function (guide) {
			var y = $author$project$Mario$Dashboard$Chart$valueY$(config, guide.r);
			return _List_fromArray(
				[
					A2(
					$elm$svg$Svg$line,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x1(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotLeft)),
							$elm$svg$Svg$Attributes$x2(
							$elm$core$String$fromFloat(config.g$ - $author$project$Mario$Dashboard$Chart$plotRight)),
							$elm$svg$Svg$Attributes$y1(
							$elm$core$String$fromFloat(y)),
							$elm$svg$Svg$Attributes$y2(
							$elm$core$String$fromFloat(y)),
							$elm$svg$Svg$Attributes$stroke(guide.ht),
							$elm$svg$Svg$Attributes$strokeWidth('1.25'),
							$elm$svg$Svg$Attributes$strokeDasharray('6 4')
						]),
					_List_Nil),
					A2(
					$elm$svg$Svg$text_,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotLeft + 4)),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat(y - 5)),
							$elm$svg$Svg$Attributes$textAnchor('start'),
							$elm$svg$Svg$Attributes$fontSize('10'),
							$elm$svg$Svg$Attributes$fill(guide.ht),
							$elm$svg$Svg$Attributes$fontFamily('ui-monospace, Menlo, Consolas, monospace')
						]),
					_List_fromArray(
						[
							$elm$svg$Svg$text(guide.n)
						]))
				]);
		},
		config.f6);
};
var $author$project$Mario$Dashboard$Chart$viewHitTargets$ = function (config, total) {
	var bandWidth = (total <= 1) ? $author$project$Mario$Dashboard$Chart$plotWidth(config) : ($author$project$Mario$Dashboard$Chart$plotWidth(config) / (total - 1));
	return $elm$core$List$indexedMap$(
		F2(
			function (i, _v0) {
				return A2(
					$elm$svg$Svg$rect,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$x(
							$elm$core$String$fromFloat(
								$author$project$Mario$Dashboard$Chart$slotX$(config, total, i) - (bandWidth / 2))),
							$elm$svg$Svg$Attributes$y(
							$elm$core$String$fromFloat($author$project$Mario$Dashboard$Chart$plotTop)),
							$elm$svg$Svg$Attributes$width(
							$elm$core$String$fromFloat(bandWidth)),
							$elm$svg$Svg$Attributes$height(
							$elm$core$String$fromFloat((config.f8 - $author$project$Mario$Dashboard$Chart$plotTop) - $author$project$Mario$Dashboard$Chart$plotBottom)),
							$elm$svg$Svg$Attributes$fill('transparent'),
							$elm$svg$Svg$Events$onMouseOver(
							config.gu(i)),
							$elm$svg$Svg$Events$onClick(
							config.gu(i))
						]),
					_List_Nil);
			}),
		config.g6);
};
var $author$project$Mario$Dashboard$Chart$viewHitTargets = F2($author$project$Mario$Dashboard$Chart$viewHitTargets$);
var $author$project$Mario$Dashboard$Chart$viewLegend = function (config) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('chart-legend')
			]),
		_Utils_ap(
			$elm$core$List$map$(
				function (s) {
					return A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('key')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('line'),
										A2($elm$html$Html$Attributes$style, 'border-top-color', s.ht),
										A2(
										$elm$html$Html$Attributes$style,
										'border-top-style',
										s.c0 ? 'dashed' : 'solid')
									]),
								_List_Nil),
								$elm$html$Html$text(s.n)
							]));
				},
				config.gM),
			$elm$core$List$map$(
				function (guide) {
					return A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('key')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$span,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('line'),
										A2($elm$html$Html$Attributes$style, 'border-top-color', guide.ht),
										A2($elm$html$Html$Attributes$style, 'border-top-style', 'dashed')
									]),
								_List_Nil),
								$elm$html$Html$text(guide.n)
							]));
				},
				config.f6)));
};
var $author$project$Mario$Dashboard$Chart$readoutItem$ = function (label, value) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('ro-item')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('ro-label')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(label)
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('ro-value')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(value)
					]))
			]));
};
var $author$project$Mario$Dashboard$Chart$readoutItem = F2($author$project$Mario$Dashboard$Chart$readoutItem$);
var $author$project$Mario$Dashboard$Chart$viewReadout$ = function (config, total) {
	var _v0 = config.f9;
	if (_v0.$ === 1) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('chart-readout'),
					$elm$html$Html$Attributes$id(config.dM)
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('ro-value')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('Hover or tap a point, or focus the chart and use the arrow keys, to read exact values.')
						]))
				]));
	} else {
		var raw = _v0.a;
		var index = $author$project$Mario$Dashboard$Chart$clampIndex$(total, raw);
		var label = $elm$core$Maybe$withDefault$(
			'',
			$elm$core$List$head(
				$elm$core$List$drop$(index, config.g6)));
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('chart-readout'),
					$elm$html$Html$Attributes$id(config.dM)
				]),
			A2(
				$elm$core$List$cons,
				$author$project$Mario$Dashboard$Chart$readoutItem$('Sample', label),
				$elm$core$List$map$(
					function (s) {
						return $author$project$Mario$Dashboard$Chart$readoutItem$(
							s.n,
							function () {
								var _v1 = $author$project$Mario$Dashboard$Chart$sampleAt$(index, s.cV);
								if (!_v1.$) {
									var v = _v1.a;
									return config.f$(v);
								} else {
									return 'not measured';
								}
							}());
					},
					config.gM)));
	}
};
var $author$project$Mario$Dashboard$Chart$viewReadout = F2($author$project$Mario$Dashboard$Chart$viewReadout$);
var $elm$svg$Svg$Attributes$points = _VirtualDom_attribute('points');
var $elm$svg$Svg$polyline = $elm$svg$Svg$trustedNode('polyline');
var $author$project$Mario$Dashboard$Chart$runs = function (values) {
	var indexed = $elm$core$List$indexedMap$($elm$core$Tuple$pair, values);
	var flush = F2(
		function (current, done) {
			return $elm$core$List$isEmpty(current) ? done : A2(
				$elm$core$List$cons,
				$elm$core$List$reverse(current),
				done);
		});
	var step = F2(
		function (_v2, _v3) {
			var i = _v2.a;
			var value = _v2.b;
			var current = _v3.a;
			var done = _v3.b;
			if (value.$ === 1) {
				return _Utils_Tuple2(
					_List_Nil,
					A2(flush, current, done));
			} else {
				var v = value.a;
				return _Utils_Tuple2(
					A2(
						$elm$core$List$cons,
						_Utils_Tuple2(i, v),
						current),
					done);
			}
		});
	var _v0 = $elm$core$List$foldl$(
		step,
		_Utils_Tuple2(_List_Nil, _List_Nil),
		indexed);
	var leftover = _v0.a;
	var collected = _v0.b;
	return $elm$core$List$reverse(
		A2(flush, leftover, collected));
};
var $elm$svg$Svg$Attributes$strokeLinecap = _VirtualDom_attribute('stroke-linecap');
var $elm$svg$Svg$Attributes$strokeLinejoin = _VirtualDom_attribute('stroke-linejoin');
var $author$project$Mario$Dashboard$Chart$viewSeries$ = function (config, total, s) {
	var toPoint = function (_v1) {
		var i = _v1.a;
		var v = _v1.b;
		return $elm$core$String$fromFloat(
			$author$project$Mario$Dashboard$Chart$slotX$(config, total, i)) + (',' + $elm$core$String$fromFloat(
			$author$project$Mario$Dashboard$Chart$valueY$(config, v)));
	};
	var measuredRuns = $author$project$Mario$Dashboard$Chart$runs(s.cV);
	var lineOf = function (run) {
		return ($elm$core$List$length(run) < 2) ? _List_Nil : _List_fromArray(
			[
				A2(
				$elm$svg$Svg$polyline,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$points(
						$elm$core$String$join$(
							' ',
							$elm$core$List$map$(toPoint, run))),
						$elm$svg$Svg$Attributes$fill('none'),
						$elm$svg$Svg$Attributes$stroke(s.ht),
						$elm$svg$Svg$Attributes$strokeWidth(
						$elm$core$String$fromFloat(s.jv)),
						$elm$svg$Svg$Attributes$strokeLinecap('round'),
						$elm$svg$Svg$Attributes$strokeLinejoin('round'),
						$elm$svg$Svg$Attributes$strokeDasharray(
						s.c0 ? '5 4' : 'none')
					]),
				_List_Nil)
			]);
	};
	var dotsOf = function (run) {
		return (s.kp || ($elm$core$List$length(run) === 1)) ? $elm$core$List$map$(
			function (_v0) {
				var i = _v0.a;
				var v = _v0.b;
				return A2(
					$elm$svg$Svg$circle,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$cx(
							$elm$core$String$fromFloat(
								$author$project$Mario$Dashboard$Chart$slotX$(config, total, i))),
							$elm$svg$Svg$Attributes$cy(
							$elm$core$String$fromFloat(
								$author$project$Mario$Dashboard$Chart$valueY$(config, v))),
							$elm$svg$Svg$Attributes$r('2.6'),
							$elm$svg$Svg$Attributes$fill(s.ht)
						]),
					_List_Nil);
			},
			run) : _List_Nil;
	};
	return $elm$core$List$concatMap$(
		function (run) {
			return _Utils_ap(
				lineOf(run),
				dotsOf(run));
		},
		measuredRuns);
};
var $author$project$Mario$Dashboard$Chart$viewSeries = F3($author$project$Mario$Dashboard$Chart$viewSeries$);
var $author$project$Mario$Dashboard$Chart$view = function (config) {
	var total = $elm$core$List$length(config.g6);
	return (!total) ? A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('placeholder')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$strong,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text('No samples yet')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(config.fW)
					]))
			])) : A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('chart-wrap')
			]),
		_List_fromArray(
			[
				A2(
				$elm$svg$Svg$svg,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('chart-svg'),
						$elm$svg$Svg$Attributes$viewBox(
						'0 0 ' + ($elm$core$String$fromFloat(config.g$) + (' ' + $elm$core$String$fromFloat(config.f8)))),
						$elm$svg$Svg$Attributes$preserveAspectRatio('none'),
						A2($elm$html$Html$Attributes$attribute, 'role', 'group'),
						A2($elm$html$Html$Attributes$attribute, 'tabindex', '0'),
						A2(
						$elm$html$Html$Attributes$attribute,
						'aria-label',
						$author$project$Mario$Dashboard$Chart$ariaLabel$(config, total)),
						A2($elm$html$Html$Attributes$attribute, 'aria-describedby', config.dM),
						$elm$html$Html$Events$preventDefaultOn$(
						'keydown',
						$author$project$Mario$Dashboard$Chart$arrowDecoder$(config, total)),
						$elm$svg$Svg$Events$onMouseOut(config.gv)
					]),
				_Utils_ap(
					$author$project$Mario$Dashboard$Chart$viewGrid$(config, total),
					_Utils_ap(
						$author$project$Mario$Dashboard$Chart$viewGuides(config),
						_Utils_ap(
							$elm$core$List$concatMap$(
								A2($author$project$Mario$Dashboard$Chart$viewSeries, config, total),
								config.gM),
							_Utils_ap(
								$author$project$Mario$Dashboard$Chart$viewCrosshair$(config, total),
								$author$project$Mario$Dashboard$Chart$viewHitTargets$(config, total)))))),
				$author$project$Mario$Dashboard$Chart$viewLegend(config),
				$author$project$Mario$Dashboard$Chart$viewReadout$(config, total)
			]));
};
var $author$project$Mario$Dashboard$viewNodesChart$ = function (tips, model, status) {
	var values = $elm$core$List$map$(
		function (h) {
			return $elm$core$Maybe$Just(h.iE);
		},
		status.c6);
	var top = $author$project$Mario$Dashboard$maxOf(values);
	return $author$project$Mario$Dashboard$chartPanel$(
		tips,
		$author$project$Mario$Dashboard$Copy$nodesChart,
		'Champion nodes',
		status,
		$author$project$Mario$Dashboard$Chart$view(
			{
				dM: 'readout-nodes',
				fW: 'No generations have been scored yet.',
				f$: $author$project$Mario$Dashboard$Format$decimal(0),
				f6: _List_fromArray(
					[
						{
						ht: '#56618a',
						n: $elm$core$String$fromInt($author$project$Mario$Dashboard$Slots$hiddenFirst) + ' fixed',
						r: $author$project$Mario$Dashboard$Slots$hiddenFirst
					}
					]),
				f8: 190,
				f9: model.cI,
				gu: $author$project$Mario$Dashboard$NodesHover,
				gv: $author$project$Mario$Dashboard$NodesLeave,
				gM: _List_fromArray(
					[
						$author$project$Mario$Dashboard$Chart$series$('nodes', 'Nodes', '#4fd6e0', values)
					]),
				g$: 400,
				g6: $author$project$Mario$Dashboard$historyLabels(status),
				g7: top,
				g8: 0,
				g9: $author$project$Mario$Dashboard$countTicks(top)
			}));
};
var $author$project$Mario$Dashboard$viewNodesChart = F3($author$project$Mario$Dashboard$viewNodesChart$);
var $author$project$Mario$Dashboard$Copy$board = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'board',
	'Active board',
	'Every ordered matchup the run trains on, and it is all of them from generation one. Our ship against their ship is a different cell from the reverse, so both orientations are counted separately. Nothing here is earned: this is the size of the problem, never progress through it.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count of ordered pairs.'),
			_Utils_Tuple2('Window', 'Fixed for the lifetime of the run.'),
			_Utils_Tuple2('Source', 'The engine\'s board definition.')
		]));
var $author$project$Mario$Dashboard$Scoring$crewRatioLines$ = function (caps, reported) {
	return _Utils_ap(
		_List_fromArray(
			[
				'Fitness is (our surviving crew \u00F7 our starting crew) \u00F7 (their surviving crew \u00F7 their starting crew), both sides measured as a share of the crew they began with, counted the moment the fight stops.',
				'1.00 means both sides kept the same share of their crew. It is a raw ratio, not a win percentage and not a fraction of maximum health, so it can sit well above 1.00 while the fight itself was never won.',
				'A ship that gains crew during the fight can hold more than its starting complement, so a share above 100% on either side is legitimate rather than a bug.',
				function () {
				var _v0 = caps.hb;
				if (!_v0.$) {
					var cap = _v0.a;
					return 'Wiping the other side out while any of ours survive scores ' + ($author$project$Mario$Dashboard$Format$decimal$(0, cap) + ', the run\'s finite stand-in for dividing by nobody.');
				} else {
					return 'Wiping the other side out while any of ours survive scores the run\'s finite stand-in for dividing by nobody, and this run did not report what that value is.';
				}
			}(),
				function () {
				var _v1 = caps.gm;
				if (!_v1.$) {
					var even = _v1.a;
					return 'Both crews at zero scores ' + ($author$project$Mario$Dashboard$Format$decimal$(0, even) + ': a mutual wipe is even, not a win and not a loss.');
				} else {
					return 'Both crews at zero is treated as even, and this run did not report the value it scores.';
				}
			}(),
				'Losing our whole crew while any of theirs survive scores 0.'
			]),
		function () {
			var _v2 = reported.fp;
			if (!_v2.$) {
				if (!_v2.a) {
					return _List_fromArray(
						['There is no time bonus: the same crew ratio scores the same whether the fight ended in two seconds or ran to the cut-off.']);
				} else {
					return _List_fromArray(
						['This run also reports a speed bonus, so a quicker finish scores higher than the same crew ratio reached later.']);
				}
			} else {
				return _List_fromArray(
					['This run does not report whether a time bonus applies.']);
			}
		}());
};
var $author$project$Mario$Dashboard$Scoring$crewRatioLines = F2($author$project$Mario$Dashboard$Scoring$crewRatioLines$);
var $author$project$Mario$Dashboard$Scoring$displayHz = 60;
var $author$project$Mario$Dashboard$Scoring$fightSeconds = function (resources) {
	return $elm$core$Maybe$andThen$(
		function (ticks) {
			return (ticks > 0) ? $elm$core$Maybe$Just(ticks / $author$project$Mario$Dashboard$Scoring$displayHz) : $elm$core$Maybe$Nothing;
		},
		resources.eT);
};
var $author$project$Mario$Dashboard$Scoring$fightLimit = function (resources) {
	return $elm$core$Maybe$map$(
		function (seconds) {
			return _Utils_eq(
				seconds,
				$elm$core$Basics$round(seconds)) ? ($author$project$Mario$Dashboard$Format$decimal$(0, seconds) + ' s') : ($author$project$Mario$Dashboard$Format$decimal$(1, seconds) + ' s');
		},
		$author$project$Mario$Dashboard$Scoring$fightSeconds(resources));
};
var $author$project$Mario$Dashboard$Scoring$explain$ = function (scoring, resources) {
	var penaltyLine = function () {
		var _v3 = $elm$core$Maybe$map$(
			function ($) {
				return $.kD;
			},
			scoring);
		if ((!_v3.$) && (_v3.a.$ === 1)) {
			var magnitude = _v3.a.a;
			return _List_fromArray(
				[
					'One condition overrides the rule above: if their crew ends no smaller than it started, fitness is ' + ('\u2212' + ($author$project$Mario$Dashboard$Format$decimal$(0, magnitude) + ' instead.'))
				]);
		} else {
			return _List_Nil;
		}
	}();
	var deadline = function () {
		var _v2 = $author$project$Mario$Dashboard$Scoring$fightLimit(resources);
		if (!_v2.$) {
			var limit = _v2.a;
			return _List_fromArray(
				['A fight is scored when it ends. One that neither side has finished is cut off at ' + (limit + ' of simulated time, not of machine time, and scored where it stands.')]);
		} else {
			return _List_fromArray(
				['A fight is scored when it ends, or at a cut-off if neither side has finished. This run does not report that cut-off, so how long a fight may run is unknown.']);
		}
	}();
	if (scoring.$ === 1) {
		return _Utils_ap(
			_List_fromArray(
				['This run published no scoring block, which means the original combat fitness: the only rule the build that wrote it had. It is not the crew ratio.']),
			deadline);
	} else {
		var reported = scoring.a;
		var _v1 = reported.kc;
		switch (_v1.$) {
			case 1:
				var caps = _v1.a;
				return _Utils_ap(
					$author$project$Mario$Dashboard$Scoring$crewRatioLines$(caps, reported),
					_Utils_ap(penaltyLine, deadline));
			case 0:
				return _Utils_ap(
					_List_fromArray(
						['A win scores one point, the crew margin adds up to 0.20 and a quick finish up to 0.02, so any win outranks any non-win and the margins only order wins among themselves.']),
					_Utils_ap(penaltyLine, deadline));
			default:
				var other = _v1.a;
				return _Utils_ap(
					_List_fromArray(
						['This run reports its scoring rule as \"' + (other + '\", which this dashboard does not recognise. It is shown verbatim rather than guessed at, and nothing on this page interprets it.')]),
					_Utils_ap(penaltyLine, deadline));
		}
	}
};
var $author$project$Mario$Dashboard$Scoring$explain = F2($author$project$Mario$Dashboard$Scoring$explain$);
var $author$project$Mario$Dashboard$Copy$fightLimit = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'fight-limit',
	'Fight length',
	'How long a fight may run in the simulation before it is cut off and scored where it stands. A fight that ends is scored when it ends; only one that neither side has finished runs to this limit. Under the crew ratio the two are scored by exactly the same rule, with no bonus for finishing early.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; simulated time, the reported episode tick budget over 60 simulation ticks per second. It is not machine wall time, and a fight takes far less of that to run.'),
			_Utils_Tuple2('Window', 'Each individual episode.'),
			_Utils_Tuple2('Source', 'Trainer resource caps, field episode_ticks.')
		]));
var $author$project$Mario$Dashboard$Copy$fitnessRule = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'fitness-rule',
	'Scoring rule',
	'What the trainer maximises when it decides which genomes breed. A crew ratio is a ratio of two shares, not a percentage of anything: 1.00 means both sides kept the same share of the crew they started with, and a value above 1.00 says our side kept more, not that the fight was won. It is not a fraction of maximum health, and it is not the gate.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'The opponent\'s surviving share of their starting crew; a ratio of two shares has no percentage denominator of its own.'),
			_Utils_Tuple2('Window', 'Every episode scored in the current generation, read when the fight ends, or at the cut-off if neither side has finished by then.'),
			_Utils_Tuple2('Source', 'Trainer configuration, republished with every status snapshot.')
		]));
var $author$project$Mario$Dashboard$Scoring$formula = function (scoring) {
	if (scoring.$ === 1) {
		return 'not reported; a run without the selector has only this rule';
	} else {
		var reported = scoring.a;
		var _v1 = reported.kc;
		switch (_v1.$) {
			case 1:
				return 'our surviving share \u00F7 theirs, 1.00 is even';
			case 0:
				return 'a win, then the crew margin, then speed';
			default:
				return 'a rule this dashboard does not know, shown as reported';
		}
	}
};
var $author$project$Mario$Dashboard$Scoring$label = function (scoring) {
	if (scoring.$ === 1) {
		return $author$project$Mario$Dashboard$Api$fitnessLabel($author$project$Mario$Dashboard$Api$Combat);
	} else {
		var reported = scoring.a;
		return $author$project$Mario$Dashboard$Api$fitnessLabel(reported.kc);
	}
};
var $author$project$Mario$Dashboard$Scoring$limitNote = function (scoring) {
	var _v0 = $elm$core$Maybe$andThen$(
		function ($) {
			return $.fp;
		},
		scoring);
	if (!_v0.$) {
		if (!_v0.a) {
			return 'simulated, for a fight nobody finishes, and no time bonus';
		} else {
			return 'simulated, for a fight nobody finishes; a quicker win scores higher';
		}
	} else {
		return 'simulated, for a fight nobody finishes, then scored where it stands';
	}
};
var $author$project$Mario$Dashboard$Copy$noDamagePenalty = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'no-damage-penalty',
	'No-damage penalty',
	'A conditional replacement for fitness, not an adjustment to it. When a fight ends with the other side\'s crew no smaller than the number it started with, the genome\'s fitness becomes the negative of this magnitude and the run\'s ordinary scoring rule is not consulted. It reads their crew at the end against their crew at the start, so it says nothing about damage we dealt and later lost to their recovery.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; it is a fitness value in the run\'s own scoring units, reported as a positive magnitude and applied negated.'),
			_Utils_Tuple2('Window', 'Each individual episode, judged at the moment the fight stops.'),
			_Utils_Tuple2('Source', 'Trainer scoring block, field no_damage_penalty. Absent or zero means the run applies none.')
		]));
var $author$project$Mario$Dashboard$Copy$nowPlaying = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'now-playing',
	'What it is playing',
	'What the trainer is spending its next episodes on: which gate round is in flight if any, how the shared training panel is drawn, and the rules every one of those fights is scored under. None of this says how good the champion is; it says what question is currently being asked of it.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Varies per row; each states its own.'),
			_Utils_Tuple2('Window', 'The generation in flight.'),
			_Utils_Tuple2('Source', 'Trainer scheduling and run configuration, republished with every snapshot.')
		]));
var $author$project$Mario$Dashboard$Scoring$penaltyExplain = function (scoring) {
	var _v0 = $elm$core$Maybe$map$(
		function ($) {
			return $.kD;
		},
		scoring);
	if (!_v0.$) {
		if (_v0.a.$ === 1) {
			var magnitude = _v0.a.a;
			return _List_fromArray(
				[
					'When a fight ends with their crew at or above the number it started with, fitness is not the ordinary score at all: it is replaced by ' + ('\u2212' + ($author$project$Mario$Dashboard$Format$decimal$(0, magnitude) + '.')),
					'The condition compares their crew at the end against their crew at the start. It is not a measure of damage we dealt: an opponent we hurt and who then took on replacements counts the same as one we never touched.',
					'The penalty moves fitness only. It changes which genomes breed and nothing about whether the run may move on: the gate is judged separately, on its own evidence.'
				]);
		} else {
			var _v1 = _v0.a;
			return _List_fromArray(
				['This run applies no no-damage penalty: a fight that leaves the other side no smaller than it started is scored by the ordinary rule, with nothing subtracted.']);
		}
	} else {
		return _List_fromArray(
			['This run published no scoring block, so it predates the no-damage penalty and applies none. Its fitness is the original combat rule throughout.']);
	}
};
var $author$project$Mario$Dashboard$Scoring$penaltyLabel = function (scoring) {
	var _v0 = $elm$core$Maybe$map$(
		function ($) {
			return $.kD;
		},
		scoring);
	if ((!_v0.$) && (_v0.a.$ === 1)) {
		var magnitude = _v0.a.a;
		return $elm$core$Maybe$Just(
			'\u2212' + $author$project$Mario$Dashboard$Format$decimal$(0, magnitude));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $author$project$Mario$Dashboard$Scoring$penaltyNote = function (scoring) {
	var _v0 = $elm$core$Maybe$map$(
		function ($) {
			return $.kD;
		},
		scoring);
	if ((!_v0.$) && (_v0.a.$ === 1)) {
		return 'fitness when they end no smaller than they started';
	} else {
		return 'no penalty for a fight that costs them nothing';
	}
};
var $author$project$Mario$Dashboard$Copy$phase = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'phase',
	'Trainer phase',
	'What the trainer is doing right now. Training means it is playing sampled episodes and breeding the next generation. Auditing means it has frozen a candidate and is spending its audit budget on fresh gate episodes. Paused means the loop is halted at a safe boundary and can resume exactly.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; this is a state, not a rate.'),
			_Utils_Tuple2('Window', 'Instantaneous, as of the last successful poll.'),
			_Utils_Tuple2('Source', 'Trainer process state.')
		]));
var $author$project$Mario$Dashboard$Copy$samplerCoverage = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'sampler-coverage',
	'Training sampler',
	'How each generation\'s shared training panel is drawn. One part is a balanced rotation that walks own and opponent hulls evenly across generations from a checkpointed cursor, so coverage cannot drift; the rest is drawn adaptively toward cells that look uncertain or learnable. The balanced share is a property of how the panel is built, not a measurement of how much of the 625-cell board has been seen.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Episodes per generation in the shared panel, and the share of it reserved for the balanced rotation.'),
			_Utils_Tuple2('Window', 'Per generation; the cursor and completed tours are cumulative over the run.'),
			_Utils_Tuple2('Source', 'Training sampler configuration and its checkpointed rotation state. Not gate evidence.')
		]));
var $author$project$Mario$Dashboard$viewNowPlaying$ = function (tips, status) {
	var samplerRows = function (sampler) {
		return _List_fromArray(
			[
				A2(
				$elm$html$Html$dt,
				_List_Nil,
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						$author$project$Mario$Dashboard$Copy$samplerCoverage,
						_List_fromArray(
							[
								$elm$html$Html$text('Training panel')
							]))
					])),
				A2(
				$elm$html$Html$dd,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(
						function () {
							var _v4 = sampler.cJ;
							if (!_v4.$) {
								var episodes = _v4.a;
								return $elm$core$String$fromInt(episodes) + ' shared episodes per generation, same panel for every genome';
							} else {
								return 'size not reported';
							}
						}())
					])),
				A2(
				$elm$html$Html$dt,
				_List_Nil,
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						$author$project$Mario$Dashboard$Copy$samplerCoverage,
						_List_fromArray(
							[
								$elm$html$Html$text('Balanced share')
							]))
					])),
				A2(
				$elm$html$Html$dd,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(
						function () {
							var _v5 = sampler.jJ;
							if (!_v5.$) {
								var share = _v5.a;
								return $author$project$Mario$Dashboard$Format$percent1(share) + ' of that panel drawn by the balanced rotation, the rest drawn adaptively';
							} else {
								return $author$project$Mario$Dashboard$Format$awaiting;
							}
						}())
					])),
				A2(
				$elm$html$Html$dt,
				_List_Nil,
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						$author$project$Mario$Dashboard$Copy$samplerCoverage,
						_List_fromArray(
							[
								$elm$html$Html$text('Rotation')
							]))
					])),
				A2(
				$elm$html$Html$dd,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text(
						function () {
							var _v6 = _Utils_Tuple2(sampler.jY, sampler.lq);
							if (!_v6.a.$) {
								if (!_v6.b.$) {
									var cursor = _v6.a.a;
									var tour = _v6.b.a;
									return 'cursor at ' + ($author$project$Mario$Dashboard$Format$count(cursor) + (', ' + ($elm$core$String$fromInt(tour) + ' full tours of the board completed')));
								} else {
									var cursor = _v6.a.a;
									var _v7 = _v6.b;
									return 'cursor at ' + ($author$project$Mario$Dashboard$Format$count(cursor) + ', completed tours not reported');
								}
							} else {
								if (!_v6.b.$) {
									var _v8 = _v6.a;
									var tour = _v6.b.a;
									return $elm$core$String$fromInt(tour) + ' full tours completed, cursor not reported';
								} else {
									var _v9 = _v6.a;
									var _v10 = _v6.b;
									return $author$project$Mario$Dashboard$Format$awaiting;
								}
							}
						}())
					]))
			]);
	};
	var opponents = $elm$core$List$foldl$(
		F2(
			function (kind, acc) {
				return $elm$core$List$member$(kind, acc) ? acc : _Utils_ap(
					acc,
					_List_fromArray(
						[kind]));
			}),
		_List_Nil,
		$elm$core$List$map$(
			function ($) {
				return $.gx;
			},
			status.dd));
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$nowPlaying,
		'What it is playing',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metrics')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: 'metric-cyan',
							n: 'Active board',
							v: 'ordered matchups, all active from generation one',
							w: $author$project$Mario$Dashboard$Copy$board,
							r: (status.fH.ji > 0) ? $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(status.fH.ji)) : $elm$core$Maybe$Nothing
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: function () {
								var _v0 = $elm$core$Maybe$map$(
									function ($) {
										return $.kc;
									},
									status.m);
								if ((!_v0.$) && (_v0.a.$ === 1)) {
									return 'metric-cyan';
								} else {
									return '';
								}
							}(),
							n: 'Fitness',
							v: $author$project$Mario$Dashboard$Scoring$formula(status.m),
							w: $author$project$Mario$Dashboard$Tip$detail$(
								$author$project$Mario$Dashboard$Copy$fitnessRule,
								$author$project$Mario$Dashboard$Scoring$explain$(status.m, status.gJ)),
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Scoring$label(status.m))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Fight limit',
							v: $author$project$Mario$Dashboard$Scoring$limitNote(status.m),
							w: $author$project$Mario$Dashboard$Copy$fightLimit,
							r: $author$project$Mario$Dashboard$Scoring$fightLimit(status.gJ)
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: function () {
								var _v1 = $elm$core$Maybe$map$(
									function ($) {
										return $.kD;
									},
									status.m);
								if ((!_v1.$) && (_v1.a.$ === 1)) {
									return 'metric-amber';
								} else {
									return '';
								}
							}(),
							n: 'No-damage penalty',
							v: $author$project$Mario$Dashboard$Scoring$penaltyNote(status.m),
							w: $author$project$Mario$Dashboard$Tip$detail$(
								$author$project$Mario$Dashboard$Copy$noDamagePenalty,
								$author$project$Mario$Dashboard$Scoring$penaltyExplain(status.m)),
							r: $author$project$Mario$Dashboard$Scoring$penaltyLabel(status.m)
						})
					])),
				A2(
				$elm$html$Html$dl,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('deflist'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
					]),
				_Utils_ap(
					_List_fromArray(
						[
							A2(
							$elm$html$Html$dt,
							_List_Nil,
							_List_fromArray(
								[
									$author$project$Mario$Dashboard$Tip$view$(
									tips,
									0,
									$author$project$Mario$Dashboard$Copy$phase,
									_List_fromArray(
										[
											$elm$html$Html$text('Doing now')
										]))
								])),
							A2(
							$elm$html$Html$dd,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									_Utils_ap(
										$author$project$Mario$Dashboard$Api$phaseLabel(status.bz),
										function () {
											var _v2 = $elm$core$Maybe$andThen$(
												function ($) {
													return $.gK;
												},
												status.cd);
											if (!_v2.$) {
												var round = _v2.a;
												return ', ' + ($author$project$Mario$Dashboard$Api$overallRoundLabel(round) + ' round in flight');
											} else {
												return ', no gate round in flight';
											}
										}()))
								])),
							A2(
							$elm$html$Html$dt,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Opponents')
								])),
							A2(
							$elm$html$Html$dd,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text(
									$elm$core$List$isEmpty(opponents) ? 'not reported' : $elm$core$String$join$(
										', ',
										$elm$core$List$map$($author$project$Mario$Dashboard$Api$opponentTypeLabel, opponents)))
								]))
						]),
					function () {
						var _v3 = status.k6;
						if (!_v3.$) {
							var sampler = _v3.a;
							return samplerRows(sampler);
						} else {
							return _List_Nil;
						}
					}()))
			]));
};
var $author$project$Mario$Dashboard$viewNowPlaying = F2($author$project$Mario$Dashboard$viewNowPlaying$);
var $author$project$Mario$Dashboard$Copy$phaseSplit = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'phase-split',
	'Where the time went',
	'This session\'s CPU seconds, split across the named phases. Shares are of ACCOUNTED time, so they sum to one and the leftover is reported on its own line rather than folded into a bucket. That leftover is signed and both signs mean something: positive is CPU nobody put a clock around, and negative means worker threads were preempted mid-fight, so its size is a contention signal rather than an error.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Accounted seconds for the shares; session CPU seconds for the unaccounted line.'),
			_Utils_Tuple2('Window', 'This process only, over the span its compute seconds cover.'),
			_Utils_Tuple2('Source', 'Per-fight clocks inside the evaluator, plus the supervisor\'s own timers.')
		]));
var $author$project$Mario$Dashboard$unaccountedLine = function (split) {
	var _v0 = split.lu;
	if (_v0.$ === 1) {
		return $author$project$Mario$Dashboard$Format$awaiting;
	} else {
		var seconds = _v0.a;
		return ((seconds >= 0) ? '+' : '\u2212') + ($author$project$Mario$Dashboard$Format$decimal$(
			3,
			$elm$core$Basics$abs(seconds)) + ('s' + ($elm$core$Maybe$withDefault$(
			'',
			$elm$core$Maybe$map$(
				function (share) {
					return ' (' + ($author$project$Mario$Dashboard$Format$percent1(
						$elm$core$Basics$abs(share)) + ' of CPU)');
				},
				split.lv)) + ((seconds >= 0) ? ', CPU nobody clocked' : ', workers preempted mid-fight'))));
	}
};
var $author$project$Mario$Dashboard$viewPhaseSplit$ = function (tips, status) {
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$phaseSplit,
		'Where the time went',
		function () {
			var _v0 = status.kT;
			if (_v0.$ === 1) {
				return _List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('placeholder')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text($author$project$Mario$Dashboard$Format$awaiting)
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('This process has not spent any compute seconds yet, so there is no split to show. That is no measurement, not a measurement of nothing.')
									]))
							]))
					]);
			} else {
				var split = _v0.a;
				return _List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('alloc')
							]),
						$elm$core$List$map$(
							function (bucket) {
								return $author$project$Mario$Dashboard$shareRow$(
									bucket.kB,
									$elm$core$Maybe$Just(
										$author$project$Mario$Dashboard$Format$decimal$(2, bucket.i2) + 's'),
									$elm$core$Maybe$withDefault$(0, bucket.lb));
							},
							$elm$core$List$filter$(
								function (bucket) {
									return bucket.i2 > 0;
								},
								split.jL))),
						A2(
						$elm$html$Html$dl,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('deflist'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '16px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Accounted')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Mario$Dashboard$Format$decimal$(2, split.jz) + ('s of ' + ($elm$core$Maybe$withDefault$(
											$author$project$Mario$Dashboard$Format$awaiting,
											$elm$core$Maybe$map$(
												function (cpu) {
													return $author$project$Mario$Dashboard$Format$decimal$(2, cpu) + 's';
												},
												split.k9)) + (' CPU' + $elm$core$Maybe$withDefault$(
											'',
											$elm$core$Maybe$map$(
												function (share) {
													return ' (' + ($author$project$Mario$Dashboard$Format$percent1(share) + ')');
												},
												split.jA))))))
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Unaccounted')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Mario$Dashboard$unaccountedLine(split))
									])),
								A2(
								$elm$html$Html$dt,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Threads busy')
									])),
								A2(
								$elm$html$Html$dd,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										function () {
											var _v1 = split.lo;
											if (!_v1.$) {
												var busy = _v1.a;
												return $author$project$Mario$Dashboard$Format$decimal$(2, busy) + (' on average over ' + ($author$project$Mario$Dashboard$Format$decimal$(1, split.la) + 's of wall time'));
											} else {
												return $author$project$Mario$Dashboard$Format$awaiting;
											}
										}())
									]))
							])),
						A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('prose'),
								A2($elm$html$Html$Attributes$style, 'margin-top', '12px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Shares are of accounted time, so they sum to one; the leftover is on its own line rather than folded into a bucket. Positive leftover is CPU nobody clocked: the supervisor loop, pool dispatch, allocation, the server thread. Negative means workers were preempted mid-fight, so its size is a contention signal rather than an error.')
							]))
					]);
			}
		}());
};
var $author$project$Mario$Dashboard$viewPhaseSplit = F2($author$project$Mario$Dashboard$viewPhaseSplit$);
var $author$project$Mario$Dashboard$Copy$meanConnections = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'mean-connections',
	'Mean connections',
	'Average enabled connection count across the population. Networks are seeded minimal and sparse, so this starts small and rises only as link mutations survive selection.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Population size.'),
			_Utils_Tuple2('Window', 'Current generation.'),
			_Utils_Tuple2('Source', 'Genome census.')
		]));
var $author$project$Mario$Dashboard$Copy$meanNodes = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'mean-nodes',
	'Mean nodes',
	'Average node count across the population, including the fixed 117 inputs and 13 outputs. Growth above the fixed 130 is the topology the run has actually discovered.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Population size.'),
			_Utils_Tuple2('Window', 'Current generation.'),
			_Utils_Tuple2('Source', 'Genome census.')
		]));
var $author$project$Mario$Dashboard$Copy$populationPanel = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'population-panel',
	'Population and structure',
	'The state of the evolutionary machinery: how many genomes are alive, how many species they split into, and how large their graphs have grown. These say what the search is doing, not how well it is doing; the gate at the top of the page is the only thing that speaks to quality.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Varies per tile; each states its own.'),
			_Utils_Tuple2('Window', 'Current generation.'),
			_Utils_Tuple2('Source', 'Evolution loop and the genome census.')
		]));
var $author$project$Mario$Dashboard$Copy$populationSize = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'pop-size',
	'Population',
	'How many genomes are alive in the current generation. Every one of them is evaluated on the same sampled panel each generation, so their scores are comparable within that generation.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count.'),
			_Utils_Tuple2('Window', 'Current generation.'),
			_Utils_Tuple2('Source', 'Evolution loop.')
		]));
var $author$project$Mario$Dashboard$Copy$species = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'species',
	'Species',
	'How many species the population currently splits into under the compatibility measure. Speciation protects a structural innovation long enough to be optimised instead of being out-competed the generation it appears. A collapse toward one species means diversity has been lost.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count.'),
			_Utils_Tuple2('Window', 'Current generation.'),
			_Utils_Tuple2('Source', 'Speciation step.')
		]));
var $author$project$Mario$Dashboard$viewPopulation$ = function (tips, status) {
	var population = status.kV;
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$populationPanel,
		'Population and structure',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metrics')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Population',
							v: 'genomes this generation',
							w: $author$project$Mario$Dashboard$Copy$populationSize,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(population.le))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Species',
							v: 'compatibility groups',
							w: $author$project$Mario$Dashboard$Copy$species,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(population.jc))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Mean nodes',
							v: $elm$core$String$fromInt($author$project$Mario$Dashboard$Slots$hiddenFirst) + ' are fixed inputs and outputs',
							w: $author$project$Mario$Dashboard$Copy$meanNodes,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$decimal$(1, population.ku))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Mean links',
							v: 'enabled connections',
							w: $author$project$Mario$Dashboard$Copy$meanConnections,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$decimal$(1, population.kt))
						})
					]))
			]));
};
var $author$project$Mario$Dashboard$viewPopulation = F2($author$project$Mario$Dashboard$viewPopulation$);
var $author$project$Mario$Dashboard$Api$seatLabel = function (seat) {
	switch (seat.$) {
		case 0:
			return 'ours';
		case 1:
			return 'opponent';
		default:
			var other = seat.a;
			return other;
	}
};
var $elm$core$List$sortWith = _List_sortWith;
var $author$project$Mario$Dashboard$Gate$blindSpots = function (rows) {
	var rank = function (row) {
		if (row.ay <= 0) {
			return _Utils_Tuple2(1, 0);
		} else {
			var _v2 = row.e5;
			if (!_v2.$) {
				var bound = _v2.a;
				return _Utils_Tuple2(0, bound);
			} else {
				var _v3 = row.g3;
				if (!_v3.$) {
					var rate = _v3.a;
					return _Utils_Tuple2(0, rate);
				} else {
					return _Utils_Tuple2(1, 0);
				}
			}
		}
	};
	return A2(
		$elm$core$List$sortWith,
		F2(
			function (a, b) {
				var _v0 = rank(b);
				var rb = _v0.a;
				var vb = _v0.b;
				var _v1 = rank(a);
				var ra = _v1.a;
				var va = _v1.b;
				return (!_Utils_eq(ra, rb)) ? A2($elm$core$Basics$compare, ra, rb) : ((!_Utils_eq(va, vb)) ? A2($elm$core$Basics$compare, va, vb) : A2(
					$elm$core$Basics$compare,
					_Utils_Tuple2(
						$author$project$Mario$Dashboard$Api$seatLabel(a.ld),
						a.lc),
					_Utils_Tuple2(
						$author$project$Mario$Dashboard$Api$seatLabel(b.ld),
						b.lc)));
			}),
		rows);
};
var $author$project$Mario$Dashboard$Api$evidenceIsGate = function (source) {
	switch (source.$) {
		case 0:
			return true;
		case 1:
			return true;
		case 2:
			return false;
		default:
			return false;
	}
};
var $author$project$Mario$Dashboard$Api$evidenceSourceLabel = function (source) {
	switch (source.$) {
		case 0:
			return 'audit round';
		case 1:
			return 'confirm round';
		case 2:
			return 'readiness probe';
		default:
			var other = source.a;
			return other;
	}
};
var $author$project$Mario$Dashboard$Copy$shipPerformance = function (scoring) {
	return A4(
		$author$project$Mario$Dashboard$Copy$t,
		'ship-performance',
		'Per-hull blind spots',
		'The same gate evidence broken out by hull. Both columns count OUR champion\'s ' + ($author$project$Mario$Dashboard$Copy$successes(scoring) + ': the \"when piloting\" rows group those by the hull our champion flew, and the \"when facing\" rows group the very same ones by the hull it flew against. A low \"when facing\" figure means our champion does badly against that hull; it is not that hull\'s own count and not an inverse. Nothing here gates anything, and there is no per-hull minimum: this table exists to expose where an aggregate pass is hiding a weakness.'),
		_List_fromArray(
			[
				_Utils_Tuple2('Denominator', 'Per hull, the games on the current round\'s balanced panel in that grouping. A hull with no games shows as unmeasured, never as 0%.'),
				_Utils_Tuple2('Window', 'One round, the one currently frozen champion. Never pooled across champions.'),
				_Utils_Tuple2('Source', 'Labelled per row: an audit or confirm round is gate evidence; a readiness row is the cheap 250-game probe and is a diagnostic only.')
			]));
};
var $elm$html$Html$Attributes$scope = $elm$html$Html$Attributes$stringProperty('scope');
var $author$project$Mario$Dashboard$Scoring$successHeading = function (scoring) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
	switch (_v0.$) {
		case 0:
			return 'Win rate';
		case 1:
			return 'Crew-lead rate';
		default:
			return 'Gate success rate';
	}
};
var $elm$html$Html$table = _VirtualDom_node('table');
var $elm$html$Html$tbody = _VirtualDom_node('tbody');
var $elm$html$Html$td = _VirtualDom_node('td');
var $elm$html$Html$th = _VirtualDom_node('th');
var $elm$html$Html$thead = _VirtualDom_node('thead');
var $elm$html$Html$tr = _VirtualDom_node('tr');
var $author$project$Mario$Dashboard$shipTable$ = function (scoring, rows) {
	var header = function (label) {
		return A2(
			$elm$html$Html$th,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$scope('col')
				]),
			_List_fromArray(
				[
					$elm$html$Html$text(label)
				]));
	};
	var cell = F2(
		function (attrs, content) {
			return A2(
				$elm$html$Html$td,
				attrs,
				_List_fromArray(
					[
						$elm$html$Html$text(content)
					]));
		});
	var row = function (entry) {
		return A2(
			$elm$html$Html$tr,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class(
					(entry.ay <= 0) ? 'is-unknown' : '')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$th,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$scope('row')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(entry.lc)
						])),
					A2(
					cell,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('num')
						]),
					$author$project$Mario$Dashboard$Format$count(entry.ay)),
					A2(
					cell,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('num')
						]),
					(entry.ay > 0) ? $author$project$Mario$Dashboard$Format$count(entry.fD) : '\u2014'),
					A2(
					cell,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('num')
						]),
					function () {
						var _v0 = entry.g3;
						if (!_v0.$) {
							var rate = _v0.a;
							return $author$project$Mario$Dashboard$Format$percent1(rate);
						} else {
							return $author$project$Mario$Dashboard$Format$awaiting;
						}
					}()),
					A2(
					cell,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('num')
						]),
					function () {
						var _v1 = entry.e5;
						if (!_v1.$) {
							var bound = _v1.a;
							return $author$project$Mario$Dashboard$Format$percent1(bound);
						} else {
							return $author$project$Mario$Dashboard$Format$awaiting;
						}
					}()),
					A2(
					cell,
					_List_Nil,
					$author$project$Mario$Dashboard$Api$evidenceSourceLabel(entry.ja))
				]));
	};
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('ship-wrap')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$table,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('ships')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$thead,
						_List_Nil,
						_List_fromArray(
							[
								A2(
								$elm$html$Html$tr,
								_List_Nil,
								_List_fromArray(
									[
										header('Hull'),
										header('Games'),
										header(
										'Champion ' + $author$project$Mario$Dashboard$Scoring$successPlural(scoring)),
										header(
										$author$project$Mario$Dashboard$Scoring$successHeading(scoring)),
										header('Lower bound'),
										header('Evidence')
									]))
							])),
						A2(
						$elm$html$Html$tbody,
						_List_Nil,
						$elm$core$List$map$(row, rows))
					]))
			]));
};
var $author$project$Mario$Dashboard$shipTable = F2($author$project$Mario$Dashboard$shipTable$);
var $author$project$Mario$Dashboard$weakRowVerb = function (scoring) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
	if (!_v0.$) {
		return 'win';
	} else {
		return 'score';
	}
};
var $author$project$Mario$Dashboard$viewShipPerformance$ = function (tips, status) {
	var sources = $elm$core$List$foldl$(
		F2(
			function (source, acc) {
				return $elm$core$List$member$(source, acc) ? acc : _Utils_ap(
					acc,
					_List_fromArray(
						[source]));
			}),
		_List_Nil,
		$elm$core$List$map$(
			function ($) {
				return $.ja;
			},
			status.fn));
	var sourceNote = function () {
		if (!sources.b) {
			return 'no evidence published';
		} else {
			return $elm$core$String$join$(
				', ',
				$elm$core$List$map$($author$project$Mario$Dashboard$Api$evidenceSourceLabel, sources));
		}
	}();
	var section_ = F3(
		function (seat, heading, caption) {
			var rows = $author$project$Mario$Dashboard$Gate$blindSpots(
				$elm$core$List$filter$(
					function (row) {
						return _Utils_eq(row.ld, seat);
					},
					status.fn));
			if ($elm$core$List$isEmpty(rows)) {
				return _List_Nil;
			} else {
				var measured = $elm$core$List$length(
					$elm$core$List$filter$(
						function (row) {
							return row.ay > 0;
						},
						rows));
				var games = $elm$core$List$sum(
					$elm$core$List$map$(
						function ($) {
							return $.ay;
						},
						rows));
				return _List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h3,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(heading)
									])),
								A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('prose'),
										A2($elm$html$Html$Attributes$style, 'margin-top', '4px')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(caption)
									])),
								A2(
								$elm$html$Html$p,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('prose')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text(
										$author$project$Mario$Dashboard$Format$count(games) + (' games across ' + ($elm$core$String$fromInt(measured) + (' of ' + ($elm$core$String$fromInt(
											$elm$core$List$length(rows)) + (' hulls' + (((measured > 0) ? (', about ' + ($author$project$Mario$Dashboard$Format$count((games / measured) | 0) + ' each')) : '') + '. Read every rate against its own sample size.')))))))
									])),
								$author$project$Mario$Dashboard$shipTable$(status.m, rows)
							]))
					]);
			}
		});
	var diagnosticOnly = (!$elm$core$List$any$($author$project$Mario$Dashboard$Api$evidenceIsGate, sources)) && (!$elm$core$List$isEmpty(sources));
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('panel')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel-head')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$Tip$view$(
						tips,
						0,
						$author$project$Mario$Dashboard$Tip$detail$(
							$author$project$Mario$Dashboard$Copy$shipPerformance(status.m),
							_List_fromArray(
								['There is no per-hull target. A hull with no games shows as unmeasured, not as a loss, and no row here can block or unblock the overall gate.'])),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$h2,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Per-hull blind spots')
									]))
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('panel-note')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(sourceNote)
							]))
					])),
				$elm$core$List$isEmpty(status.fn) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('placeholder')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('No per-hull evidence')
							])),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('The trainer has not published per-hull figures for this round yet.')
							]))
					])) : A2(
				$elm$html$Html$div,
				_List_Nil,
				_Utils_ap(
					_List_fromArray(
						[
							A2(
							$elm$html$Html$p,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('prose')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text(
									'Both tables count our champion\'s own ' + ($author$project$Mario$Dashboard$Scoring$successPlural(status.m) + (', grouped two ways.' + (diagnosticOnly ? ' These rows are the cheap balanced readiness probe, not gate evidence.' : ''))))
								]))
						]),
					_Utils_ap(
						A3(
							section_,
							$author$project$Mario$Dashboard$Api$OurSeat,
							'When piloting',
							'Grouped by the hull our champion flew. A weak row is a hull it cannot ' + ($author$project$Mario$Dashboard$weakRowVerb(status.m) + ' with.')),
						A3(section_, $author$project$Mario$Dashboard$Api$OpponentSeat, 'When facing', 'The same games grouped by the hull it flew against. A weak row is a hull it cannot beat.'))))
			]));
};
var $author$project$Mario$Dashboard$viewShipPerformance = F2($author$project$Mario$Dashboard$viewShipPerformance$);
var $author$project$Mario$Dashboard$SpeciesHover = function (a) {
	return {$: 10, a: a};
};
var $author$project$Mario$Dashboard$SpeciesLeave = {$: 11};
var $author$project$Mario$Dashboard$Copy$structureChart = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'chart-species',
	'Species count',
	'How many species the population splits into, per generation. Speciation is what protects a new structural idea long enough to be optimised. A collapse toward one species alongside rising node counts usually means a single lineage has taken over and structural exploration has stopped.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count per generation.'),
			_Utils_Tuple2('Window', 'Per generation, whole run.'),
			_Utils_Tuple2('Source', 'Speciation step. Deliberately kept off the win rate chart so structure is never read as performance.')
		]));
var $author$project$Mario$Dashboard$viewSpeciesChart$ = function (tips, model, status) {
	var values = $elm$core$List$map$(
		function (h) {
			return $elm$core$Maybe$Just(h.jc);
		},
		status.c6);
	var top = $author$project$Mario$Dashboard$maxOf(values);
	return $author$project$Mario$Dashboard$chartPanel$(
		tips,
		$author$project$Mario$Dashboard$Copy$structureChart,
		'Species',
		status,
		$author$project$Mario$Dashboard$Chart$view(
			{
				dM: 'readout-species',
				fW: 'No generations have been scored yet.',
				f$: $author$project$Mario$Dashboard$Format$decimal(0),
				f6: _List_Nil,
				f8: 190,
				f9: model.cO,
				gu: $author$project$Mario$Dashboard$SpeciesHover,
				gv: $author$project$Mario$Dashboard$SpeciesLeave,
				gM: _List_fromArray(
					[
						$author$project$Mario$Dashboard$Chart$series$('species', 'Species', '#a99bf5', values)
					]),
				g$: 400,
				g6: $author$project$Mario$Dashboard$historyLabels(status),
				g7: top,
				g8: 0,
				g9: $author$project$Mario$Dashboard$countTicks(top)
			}));
};
var $author$project$Mario$Dashboard$viewSpeciesChart = F3($author$project$Mario$Dashboard$viewSpeciesChart$);
var $author$project$Mario$Dashboard$Copy$combatVictories = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'combat-victories',
	'Actual combat victories',
	'A count of episodes our side actually resolved in its favour, across the whole population, whatever the run is gated on. It is the one tally on this page that is a win count, and it is deliberately not a rate: it cannot be compared with the champion\'s gate figure, which is one genome\'s record on a predeclared panel. When the counter started part-way through a run its baseline is named alongside it, because the run\'s true total is then unknown.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; it is a count of episodes, not a share of them. Divide it by nothing on this page.'),
			_Utils_Tuple2('Window', 'Every episode in the counting window the trainer reports, population-wide, cumulative.'),
			_Utils_Tuple2('Source', 'Trainer field episodes_combat_wins_all_time, or the partial counter with its episode baseline when no all-time figure is published.')
		]));
var $author$project$Mario$Dashboard$Scoring$combatVictoriesNote = function (victories) {
	if (!victories.$) {
		return 'resolved victories, whole run, all episodes';
	} else {
		return 'not counted by this run';
	}
};
var $author$project$Mario$Dashboard$Scoring$combatVictoriesValue = function (victories) {
	return $elm$core$Maybe$map$($author$project$Mario$Dashboard$Format$count, victories);
};
var $author$project$Mario$Dashboard$Copy$elapsed = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'elapsed',
	'Elapsed',
	'Total wall-clock time this run has spent training, summed across every start and resume. Time while the process was stopped does not count.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a duration.'),
			_Utils_Tuple2('Window', 'Cumulative across all sessions of this run.'),
			_Utils_Tuple2('Source', 'Checkpointed elapsed totals.')
		]));
var $author$project$Mario$Dashboard$Copy$episodes = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'episodes',
	'Episodes resolved',
	'Total melee episodes simulated in this run, counting training play and audit play together. One episode is one ordered matchup played to a real resolved outcome or to the configured display-tick deadline.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count.'),
			_Utils_Tuple2('Window', 'Cumulative since the run started, preserved across resume.'),
			_Utils_Tuple2('Source', 'Training and audit episodes combined. Use the matchup grid for audit-only evidence.')
		]));
var $author$project$Mario$Dashboard$Copy$episodesPerSecond = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'throughput',
	'Throughput',
	'Episodes resolved per WALL-CLOCK second, which makes it load dependent: it falls when something else uses the machine, rises with more workers, and already reflects the duty governor\'s deliberate rest. It is a measure of how fast this session happens to be going, never of what the build costs. The nanoseconds-per-unit-of-work figures beside it are the ones that hold still.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Wall-clock seconds, including rest periods.'),
			_Utils_Tuple2('Window', 'As reported by the trainer for its recent batches.'),
			_Utils_Tuple2('Source', 'Evaluator scheduling.')
		]));
var $author$project$Mario$Dashboard$Copy$generation = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'generation',
	'Generation',
	'How many complete NEAT generations have been bred and scored. One generation evaluates every population member on the same sampled panel, then applies species allocation, crossover and mutation.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a count.'),
			_Utils_Tuple2('Window', 'Cumulative since the run started, preserved across resume.'),
			_Utils_Tuple2('Source', 'Evolution loop.')
		]));
var $author$project$Mario$Dashboard$Copy$unresolved = function (scoring) {
	return A4(
		$author$project$Mario$Dashboard$Copy$t,
		'unresolved',
		'Unresolved episodes',
		function () {
			var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
			if (_v0.$ === 1) {
				return 'Episodes that ended without a resolved combat outcome: the display-tick deadline reached with both ships still flying, and episodes ended by selection or resurrection rather than by a kill. Under this run\'s gate they are not discarded. They are scored on crew share like any other episode and can count as leads, so a rising count here does not thin out the evidence behind the rates above; it changes what kind of fight most of that evidence describes.';
			} else {
				return 'Episodes that ended without a real resolved outcome, usually two ships that never finished each other off. These are invalidated, not won. A timeout is not a victory for either side and is never scored as one, so a rising count here means the win rates above rest on fewer real fights than the episode total suggests.';
			}
		}(),
		_List_fromArray(
			[
				_Utils_Tuple2('Denominator', 'Total episodes in the run.'),
				_Utils_Tuple2('Window', 'Cumulative since the run started.'),
				_Utils_Tuple2('Source', 'Episode outcomes. Counted separately from the gate tallies precisely so it cannot be mistaken for one.')
			]));
};
var $author$project$Mario$Dashboard$Scoring$unresolvedNote = function (scoring) {
	var _v0 = $author$project$Mario$Dashboard$Scoring$criterion(scoring);
	switch (_v0.$) {
		case 0:
			return 'timed out, not won';
		case 1:
			return 'unresolved; crew leads still count';
		default:
			return 'unresolved';
	}
};
var $author$project$Mario$Dashboard$Copy$workRates = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'work-rates',
	'Cost per unit of work',
	'CPU nanoseconds this process spent per simulated display tick, and per link activation in the policy network. Both divide thread-summed CPU time by counts of events, so neither moves when the machine gets busy, when the duty governor rests, or when the worker count changes, and neither is flattered by a policy that learns to win faster and therefore simulates less. These are the figures to optimise against; episodes per second is not.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'Display ticks simulated, and link activations evaluated, by this process.'),
			_Utils_Tuple2('Window', 'This process only. The counters start at zero on every resume and are never checkpointed.'),
			_Utils_Tuple2('Source', 'Per-fight work counters over getrusage CPU time summed across all threads.')
		]));
var $author$project$Mario$Dashboard$viewThroughput$ = function (tips, model, status) {
	var work = status.jw;
	var rate = function (field) {
		return $elm$core$Maybe$andThen$(field, work);
	};
	return $author$project$Mario$Dashboard$panel$(
		tips,
		$author$project$Mario$Dashboard$Copy$workRates,
		'Throughput and cost',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('metrics')
					]),
				_List_fromArray(
					[
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: 'metric-cyan',
							n: 'CPU ns / tick',
							v: 'per simulated display tick, this process, all threads',
							w: $author$project$Mario$Dashboard$Copy$workRates,
							r: $elm$core$Maybe$map$(
								$author$project$Mario$Dashboard$Format$decimal(1),
								rate(
									function ($) {
										return $.eN;
									}))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: 'metric-cyan',
							n: 'CPU ns / link',
							v: 'per policy link activation, this process, all threads',
							w: $author$project$Mario$Dashboard$Copy$workRates,
							r: $elm$core$Maybe$map$(
								$author$project$Mario$Dashboard$Format$decimal(2),
								rate(
									function ($) {
										return $.hw;
									}))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Ticks / episode',
							v: 'shorter fights do less work, and the rates above say so',
							w: $author$project$Mario$Dashboard$Copy$workRates,
							r: $elm$core$Maybe$map$(
								$author$project$Mario$Dashboard$Format$decimal(0),
								rate(
									function ($) {
										return $.j2;
									}))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: 'metric-amber',
							n: 'Episodes / second',
							v: 'wall clock, so load dependent; not a measure of the build',
							w: $author$project$Mario$Dashboard$Copy$episodesPerSecond,
							r: (status.hF > 0) ? $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$decimal$(2, status.hF)) : $elm$core$Maybe$Nothing
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Elapsed',
							v: 'summed across resumes',
							w: $author$project$Mario$Dashboard$Copy$elapsed,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$duration(status.j4))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Generation',
							v: 'bred and scored',
							w: $author$project$Mario$Dashboard$Copy$generation,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(status.f3))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Episodes',
							v: 'training plus gate play, whole run',
							w: $author$project$Mario$Dashboard$Copy$episodes,
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(status.c4))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: ((status.c4 > 0) && (_Utils_cmp(status.fY, 0.25 * status.c4) > 0)) ? 'metric-amber' : '',
							n: 'Unresolved',
							v: (status.c4 > 0) ? ($author$project$Mario$Dashboard$Format$percent1(status.fY / status.c4) + (' ' + $author$project$Mario$Dashboard$Scoring$unresolvedNote(status.m))) : $author$project$Mario$Dashboard$Scoring$unresolvedNote(status.m),
							w: $author$project$Mario$Dashboard$Copy$unresolved(status.m),
							r: $elm$core$Maybe$Just(
								$author$project$Mario$Dashboard$Format$count(status.fY))
						}),
						$author$project$Mario$Dashboard$viewMetric$(
						tips,
						{
							u: '',
							n: 'Combat victories',
							v: $author$project$Mario$Dashboard$Scoring$combatVictoriesNote(status.hE),
							w: $author$project$Mario$Dashboard$Copy$combatVictories,
							r: $author$project$Mario$Dashboard$Scoring$combatVictoriesValue(status.hE)
						})
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '14px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						function () {
							if (work.$ === 1) {
								return 'This process has not computed yet, so there is nothing to divide by and the per-unit-of-work rates are absent rather than zero. Reading a checkpoint from disk is such a process.';
							} else {
								var measured = work.a;
								return 'Counted over this process only: ' + ($author$project$Mario$Dashboard$Format$count(measured.c4) + (' episodes, ' + ($author$project$Mario$Dashboard$Format$count(measured.j1) + (' display ticks and ' + ($author$project$Mario$Dashboard$Format$count(measured.ko) + ' link activations. The counters start at zero on every resume and are never checkpointed.')))));
							}
						}())
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						'Polling ' + ($author$project$Mario$Dashboard$statusUrl + (' every ' + ($author$project$Mario$Dashboard$Format$decimal$(0, $author$project$Mario$Dashboard$pollMillis / 1000) + (' seconds' + (model.cW ? '.' : ', slowed while this tab is hidden.'))))))
					]))
			]));
};
var $author$project$Mario$Dashboard$viewThroughput = F3($author$project$Mario$Dashboard$viewThroughput$);
var $author$project$Mario$Dashboard$NodeClear = {$: 17};
var $author$project$Mario$Dashboard$NodeSelect = function (a) {
	return {$: 16, a: a};
};
var $author$project$Mario$Dashboard$Copy$topology = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'topology',
	'Champion network',
	'The champion\'s evolved graph. The 117 inputs are grouped and individually labelled: 93 combat sensors, our ship\'s 5 identity bits, the opponent\'s 5 identity bits, the 5 control bits actually applied last step, the 8 memory channels fed back from last step, and the extra bias. The 13 outputs are the 5 controls and the 8 memory channels. Hidden nodes and every connection between them were produced by structural mutation, not by a fixed layer.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; a graph.'),
			_Utils_Tuple2('Window', 'Current champion genome, as served by the network endpoint.'),
			_Utils_Tuple2('Source', 'Genome. Connection weights are shown as stored; no activations are replayed here.')
		]));
var $author$project$Mario$Dashboard$Topology$indexOf$ = function (target, list) {
	return $elm$core$Maybe$map$(
		$elm$core$Tuple$first,
		$elm$core$List$head(
			$elm$core$List$filter$(
				function (_v0) {
					var v = _v0.b;
					return _Utils_eq(v, target);
				},
				$elm$core$List$indexedMap$($elm$core$Tuple$pair, list))));
};
var $author$project$Mario$Dashboard$Topology$indexOf = F2($author$project$Mario$Dashboard$Topology$indexOf$);
var $author$project$Mario$Dashboard$Topology$arrowDecoder$ = function (config, ids) {
	return A2(
		$elm$json$Json$Decode$andThen,
		function (key) {
			var pick = function (i) {
				return $elm$core$List$head(
					$elm$core$List$drop$(
						$elm$core$Basics$max$(
							0,
							$elm$core$Basics$min$(
								$elm$core$List$length(ids) - 1,
								i)),
						ids));
			};
			var current = $elm$core$Maybe$withDefault$(
				-1,
				$elm$core$Maybe$andThen$(
					function (s) {
						return $author$project$Mario$Dashboard$Topology$indexOf$(s, ids);
					},
					config.i4));
			var move = function (delta) {
				var _v1 = pick(current + delta);
				if (!_v1.$) {
					var id = _v1.a;
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(
							config.iI(id),
							true));
				} else {
					return $elm$json$Json$Decode$fail('edge');
				}
			};
			switch (key) {
				case 'ArrowDown':
					return move(1);
				case 'ArrowRight':
					return move(1);
				case 'ArrowUp':
					return move(-1);
				case 'ArrowLeft':
					return move(-1);
				case 'Escape':
					return $elm$json$Json$Decode$succeed(
						_Utils_Tuple2(config.iH, false));
				default:
					return $elm$json$Json$Decode$fail('ignored');
			}
		},
		A2($elm$json$Json$Decode$field, 'key', $elm$json$Json$Decode$string));
};
var $author$project$Mario$Dashboard$Topology$arrowDecoder = F2($author$project$Mario$Dashboard$Topology$arrowDecoder$);
var $elm$svg$Svg$Attributes$d = _VirtualDom_attribute('d');
var $elm$svg$Svg$defs = $elm$svg$Svg$trustedNode('defs');
var $elm$svg$Svg$Attributes$id = _VirtualDom_attribute('id');
var $elm$svg$Svg$marker = $elm$svg$Svg$trustedNode('marker');
var $elm$svg$Svg$Attributes$markerHeight = _VirtualDom_attribute('markerHeight');
var $elm$svg$Svg$Attributes$markerWidth = _VirtualDom_attribute('markerWidth');
var $elm$svg$Svg$Attributes$orient = _VirtualDom_attribute('orient');
var $elm$svg$Svg$path = $elm$svg$Svg$trustedNode('path');
var $elm$svg$Svg$Attributes$refX = _VirtualDom_attribute('refX');
var $elm$svg$Svg$Attributes$refY = _VirtualDom_attribute('refY');
var $author$project$Mario$Dashboard$Topology$defs = A2(
	$elm$svg$Svg$defs,
	_List_Nil,
	_List_fromArray(
		[
			A2(
			$elm$svg$Svg$marker,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$id('mario-recurrent-arrow'),
					$elm$svg$Svg$Attributes$viewBox('0 0 8 8'),
					$elm$svg$Svg$Attributes$refX('7'),
					$elm$svg$Svg$Attributes$refY('4'),
					$elm$svg$Svg$Attributes$markerWidth('5'),
					$elm$svg$Svg$Attributes$markerHeight('5'),
					$elm$svg$Svg$Attributes$orient('auto')
				]),
			_List_fromArray(
				[
					A2(
					$elm$svg$Svg$path,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$d('M 0 0 L 8 4 L 0 8 z'),
							$elm$svg$Svg$Attributes$fill('#f4ead6')
						]),
					_List_Nil)
				]))
		]));
var $author$project$Mario$Dashboard$Slots$Hidden = 8;
var $author$project$Mario$Dashboard$Slots$MemoryOutputs = 7;
var $author$project$Mario$Dashboard$Topology$bandGap = 10;
var $author$project$Mario$Dashboard$Topology$bottomMargin = 18;
var $author$project$Mario$Dashboard$Topology$denseColumn = 26;
var $author$project$Mario$Dashboard$Slots$Bias = 5;
var $author$project$Mario$Dashboard$Slots$ControlOutputs = 6;
var $author$project$Mario$Dashboard$Slots$OurShipBits = 1;
var $author$project$Mario$Dashboard$Slots$PriorControls = 3;
var $author$project$Mario$Dashboard$Slots$PriorMemory = 4;
var $author$project$Mario$Dashboard$Slots$Sensors = 0;
var $author$project$Mario$Dashboard$Slots$TheirShipBits = 2;
var $author$project$Mario$Dashboard$Slots$groupOf = function (id) {
	return (id < 0) ? 8 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$sensorCount) < 0) ? 0 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$sensorCount + $author$project$Mario$Dashboard$Slots$shipBits) < 0) ? 1 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$observationCount) < 0) ? 2 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$observationCount + $author$project$Mario$Dashboard$Slots$controlCount) < 0) ? 3 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$biasIndex) < 0) ? 4 : (_Utils_eq(id, $author$project$Mario$Dashboard$Slots$biasIndex) ? 5 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$outputFirst + $author$project$Mario$Dashboard$Slots$controlCount) < 0) ? 6 : ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$hiddenFirst) < 0) ? 7 : 8))))))));
};
var $author$project$Mario$Dashboard$Topology$maxDepth = 8;
var $author$project$Mario$Dashboard$Topology$orderedIds = function (genome) {
	var referenced = $elm$core$List$concatMap$(
		function (g) {
			return _List_fromArray(
				[g.f1, g.gY]);
		},
		genome.ke);
	var declared = $elm$core$List$map$(
		function ($) {
			return $.e1;
		},
		genome.iE);
	return $elm$core$Dict$keys(
		$elm$core$List$foldl$(
			F2(
				function (i, acc) {
					return $elm$core$Dict$insert$(i, 0, acc);
				}),
			$elm$core$Dict$empty,
			_Utils_ap(declared, referenced)));
};
var $author$project$Mario$Dashboard$Topology$hiddenDepths = function (genome) {
	var ids = $author$project$Mario$Dashboard$Topology$orderedIds(genome);
	var hidden = $elm$core$List$filter$(
		function (i) {
			return $author$project$Mario$Dashboard$Slots$groupOf(i) === 8;
		},
		ids);
	var initial = $elm$core$List$foldl$(
		F2(
			function (i, acc) {
				return $elm$core$Dict$insert$(i, $author$project$Mario$Dashboard$Topology$maxDepth, acc);
			}),
		$elm$core$Dict$empty,
		hidden);
	var edges = $elm$core$List$filter$(
		function (g) {
			return $author$project$Mario$Dashboard$Slots$groupOf(g.gY) === 8;
		},
		$elm$core$List$filter$(
			function ($) {
				return $.fX;
			},
			genome.ke));
	var depthOf = F2(
		function (table, id) {
			return ($author$project$Mario$Dashboard$Slots$groupOf(id) === 8) ? $elm$core$Maybe$withDefault$(
				$author$project$Mario$Dashboard$Topology$maxDepth,
				$elm$core$Dict$get$(id, table)) : 0;
		});
	var relax = function (table) {
		return $elm$core$List$foldl$(
			F2(
				function (g, acc) {
					var current = $elm$core$Maybe$withDefault$(
						$author$project$Mario$Dashboard$Topology$maxDepth,
						$elm$core$Dict$get$(g.gY, acc));
					var candidate = $elm$core$Basics$min$(
						$author$project$Mario$Dashboard$Topology$maxDepth,
						A2(depthOf, acc, g.f1) + 1);
					return (_Utils_cmp(candidate, current) < 0) ? $elm$core$Dict$insert$(g.gY, candidate, acc) : acc;
				}),
			table,
			edges);
	};
	return $elm$core$List$foldl$(
		F2(
			function (_v0, table) {
				return relax(table);
			}),
		initial,
		$elm$core$List$range$(1, $author$project$Mario$Dashboard$Topology$maxDepth));
};
var $author$project$Mario$Dashboard$Topology$hiddenRowStep = 11;
var $author$project$Mario$Dashboard$Topology$inputBands = _List_fromArray(
	[0, 1, 2, 3, 4, 5]);
var $author$project$Mario$Dashboard$Topology$inputX = 154;
var $elm$core$Dict$map$ = function (func, dict) {
	if (dict.$ === -2) {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	} else {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var right = dict.e;
		return $elm$core$Dict$RBNode_elm_builtin$(
			color,
			key,
			A2(func, key, value),
			$elm$core$Dict$map$(func, left),
			$elm$core$Dict$map$(func, right));
	}
};
var $elm$core$Dict$map = F2($elm$core$Dict$map$);
var $elm$core$Dict$member$ = function (key, dict) {
	var _v0 = $elm$core$Dict$get$(key, dict);
	if (!_v0.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Dict$member = F2($elm$core$Dict$member$);
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
var $author$project$Mario$Dashboard$Topology$outputBands = _List_fromArray(
	[6, 7]);
var $author$project$Mario$Dashboard$Topology$userWidth = 980;
var $author$project$Mario$Dashboard$Topology$outputX = $author$project$Mario$Dashboard$Topology$userWidth - 150;
var $author$project$Mario$Dashboard$Topology$rowStep = 11;
var $elm$core$Tuple$second = function (_v0) {
	var y = _v0.b;
	return y;
};
var $elm$core$List$sort = function (xs) {
	return A2($elm$core$List$sortBy, $elm$core$Basics$identity, xs);
};
var $author$project$Mario$Dashboard$Topology$topMargin = 30;
var $elm$core$Dict$values = function (dict) {
	return $elm$core$Dict$foldr$(
		F3(
			function (key, value, valueList) {
				return A2($elm$core$List$cons, value, valueList);
			}),
		_List_Nil,
		dict);
};
var $author$project$Mario$Dashboard$Topology$layout = function (genome) {
	var outputIds = $elm$core$List$range$($author$project$Mario$Dashboard$Slots$outputFirst, $author$project$Mario$Dashboard$Slots$hiddenFirst - 1);
	var inputIds = $elm$core$List$range$(0, $author$project$Mario$Dashboard$Slots$inputCount - 1);
	var inputRows = $elm$core$List$reverse(
		$elm$core$List$foldl$(
			F2(
				function (id, _v7) {
					var y = _v7.a;
					var acc = _v7.b;
					var gap = function () {
						if (acc.b) {
							var _v9 = acc.a;
							var prevId = _v9.a;
							return (!_Utils_eq(
								$author$project$Mario$Dashboard$Slots$groupOf(prevId),
								$author$project$Mario$Dashboard$Slots$groupOf(id))) ? $author$project$Mario$Dashboard$Topology$bandGap : 0;
						} else {
							return 0;
						}
					}();
					var thisY = y + gap;
					return _Utils_Tuple2(
						thisY + $author$project$Mario$Dashboard$Topology$rowStep,
						A2(
							$elm$core$List$cons,
							_Utils_Tuple2(id, thisY),
							acc));
				}),
			_Utils_Tuple2($author$project$Mario$Dashboard$Topology$topMargin, _List_Nil),
			inputIds).b);
	var inputColumnHeight = $elm$core$Maybe$withDefault$(
		$author$project$Mario$Dashboard$Topology$topMargin + $author$project$Mario$Dashboard$Topology$rowStep,
		$elm$core$List$maximum(
			$elm$core$List$map$($elm$core$Tuple$second, inputRows)));
	var ids = $author$project$Mario$Dashboard$Topology$orderedIds(genome);
	var hidden = $elm$core$List$sort(
		$elm$core$List$filter$(
			function (i) {
				return $author$project$Mario$Dashboard$Slots$groupOf(i) === 8;
			},
			ids));
	var depths = $author$project$Mario$Dashboard$Topology$hiddenDepths(genome);
	var hiddenColumns = $elm$core$Dict$map$(
		F2(
			function (_v6, v) {
				return $elm$core$List$reverse(v);
			}),
		$elm$core$List$foldl$(
			F2(
				function (_v5, acc) {
					var d = _v5.a;
					var id = _v5.b;
					return $elm$core$Dict$update$(
						d,
						function (m) {
							return $elm$core$Maybe$Just(
								A2(
									$elm$core$List$cons,
									id,
									$elm$core$Maybe$withDefault$(_List_Nil, m)));
						},
						acc);
				}),
			$elm$core$Dict$empty,
			$elm$core$List$map$(
				function (id) {
					return _Utils_Tuple2(
						$elm$core$Maybe$withDefault$(
							$author$project$Mario$Dashboard$Topology$maxDepth,
							$elm$core$Dict$get$(id, depths)),
						id);
				},
				hidden)));
	var usedDepths = $elm$core$Dict$keys(hiddenColumns);
	var widestHiddenColumn = $elm$core$Maybe$withDefault$(
		0,
		$elm$core$List$maximum(
			$elm$core$Dict$values(
				$elm$core$List$foldl$(
					F2(
						function (d, acc) {
							return $elm$core$Dict$update$(
								d,
								function (m) {
									return $elm$core$Maybe$Just(
										1 + $elm$core$Maybe$withDefault$(0, m));
								},
								acc);
						}),
					$elm$core$Dict$empty,
					$elm$core$List$map$(
						function (id) {
							return $elm$core$Maybe$withDefault$(
								$author$project$Mario$Dashboard$Topology$maxDepth,
								$elm$core$Dict$get$(id, depths));
						},
						hidden)))));
	var declaredSet = $elm$core$List$foldl$(
		F2(
			function (n, acc) {
				return $elm$core$Dict$insert$(n.e1, 0, acc);
			}),
		$elm$core$Dict$empty,
		genome.iE);
	var place = F2(
		function (x, _v4) {
			var id = _v4.a;
			var y = _v4.b;
			return {
				c1: $elm$core$Dict$member$(id, declaredSet),
				f5: $author$project$Mario$Dashboard$Slots$groupOf(id),
				e1: id,
				L: x,
				ap: y
			};
		});
	var crowded = _Utils_cmp(widestHiddenColumn, $author$project$Mario$Dashboard$Topology$denseColumn) > 0;
	var columnX = function (depth) {
		var usable = ($author$project$Mario$Dashboard$Topology$outputX - $author$project$Mario$Dashboard$Topology$inputX) - 120;
		var position = $elm$core$Maybe$withDefault$(
			0,
			$elm$core$Maybe$map$(
				$elm$core$Tuple$first,
				$elm$core$List$head(
					$elm$core$List$filter$(
						function (_v3) {
							var d = _v3.b;
							return _Utils_eq(d, depth);
						},
						$elm$core$List$indexedMap$($elm$core$Tuple$pair, usedDepths)))));
		var lanes = $elm$core$Basics$max$(
			1,
			$elm$core$List$length(usedDepths));
		return ($author$project$Mario$Dashboard$Topology$inputX + 60) + ((usable * (position + 0.5)) / lanes);
	};
	var columnHeight = $elm$core$Basics$max$(inputColumnHeight, $author$project$Mario$Dashboard$Topology$topMargin + (widestHiddenColumn * $author$project$Mario$Dashboard$Topology$hiddenRowStep));
	var height = (columnHeight + $author$project$Mario$Dashboard$Topology$rowStep) + $author$project$Mario$Dashboard$Topology$bottomMargin;
	var span_ = columnHeight - $author$project$Mario$Dashboard$Topology$topMargin;
	var hiddenRows = $elm$core$List$concatMap$(
		function (_v2) {
			var depth = _v2.a;
			var members = _v2.b;
			var n = $elm$core$List$length(members);
			var startY = (n <= 1) ? ($author$project$Mario$Dashboard$Topology$topMargin + (span_ / 2)) : $author$project$Mario$Dashboard$Topology$topMargin;
			var step = (n <= 1) ? 0 : (span_ / (n - 1));
			return $elm$core$List$indexedMap$(
				F2(
					function (i, id) {
						return _Utils_Tuple3(
							id,
							columnX(depth),
							startY + (step * i));
					}),
				members);
		},
		$elm$core$Dict$toList(hiddenColumns));
	var outputRows = function () {
		var n = $elm$core$List$length(outputIds);
		var step = (n <= 1) ? 0 : (span_ / ((n - 1) + 1));
		return $elm$core$List$indexedMap$(
			F2(
				function (i, id) {
					var extra = ($author$project$Mario$Dashboard$Slots$groupOf(id) === 7) ? step : 0;
					return _Utils_Tuple2(id, ($author$project$Mario$Dashboard$Topology$topMargin + (step * i)) + extra);
				}),
			outputIds);
	}();
	var placed = _Utils_ap(
		$elm$core$List$map$(
			place($author$project$Mario$Dashboard$Topology$inputX),
			inputRows),
		_Utils_ap(
			$elm$core$List$map$(
				place($author$project$Mario$Dashboard$Topology$outputX),
				outputRows),
			$elm$core$List$map$(
				function (_v1) {
					var id = _v1.a;
					var x = _v1.b;
					var y = _v1.c;
					return A2(
						place,
						x,
						_Utils_Tuple2(id, y));
				},
				hiddenRows)));
	var bandMarks = $elm$core$List$filterMap$(
		function (group) {
			var ys = $elm$core$List$map$(
				function ($) {
					return $.ap;
				},
				$elm$core$List$filter$(
					function (p) {
						return _Utils_eq(p.f5, group);
					},
					placed));
			var _v0 = _Utils_Tuple2(
				$elm$core$List$minimum(ys),
				$elm$core$List$maximum(ys));
			if ((!_v0.a.$) && (!_v0.b.$)) {
				var lo = _v0.a.a;
				var hi = _v0.b.a;
				return $elm$core$Maybe$Just(
					_Utils_Tuple3(group, lo, hi));
			} else {
				return $elm$core$Maybe$Nothing;
			}
		},
		_Utils_ap($author$project$Mario$Dashboard$Topology$inputBands, $author$project$Mario$Dashboard$Topology$outputBands));
	return {
		dC: bandMarks,
		dJ: crowded,
		f8: height,
		cz: $elm$core$List$foldl$(
			F2(
				function (p, acc) {
					return $elm$core$Dict$insert$(p.e1, p, acc);
				}),
			$elm$core$Dict$empty,
			placed),
		dm: placed
	};
};
var $author$project$Mario$Dashboard$Topology$summarize = function (genome) {
	var referenced = $author$project$Mario$Dashboard$Topology$orderedIds(genome);
	var lay = $author$project$Mario$Dashboard$Topology$layout(genome);
	var xOf = function (id) {
		return $elm$core$Maybe$withDefault$(
			0,
			$elm$core$Maybe$map$(
				function ($) {
					return $.L;
				},
				$elm$core$Dict$get$(id, lay.cz)));
	};
	var enabled = $elm$core$List$filter$(
		function ($) {
			return $.fX;
		},
		genome.ke);
	var declaredSet = $elm$core$List$foldl$(
		F2(
			function (n, acc) {
				return $elm$core$Dict$insert$(n.e1, 0, acc);
			}),
		$elm$core$Dict$empty,
		genome.iE);
	return {
		dN: $elm$core$List$length(genome.ke) - $elm$core$List$length(enabled),
		fX: $elm$core$List$length(enabled),
		dS: $elm$core$List$length(
			$elm$core$List$filter$(
				function (i) {
					return $author$project$Mario$Dashboard$Slots$groupOf(i) === 8;
				},
				referenced)),
		d3: $elm$core$Basics$max$(
			0.001,
			$elm$core$Maybe$withDefault$(
				1,
				$elm$core$List$maximum(
					$elm$core$List$map$(
						function (g) {
							return $elm$core$Basics$abs(g.g2);
						},
						genome.ke)))),
		iE: $elm$core$List$length(referenced),
		eo: $elm$core$List$length(
			$elm$core$List$filter$(
				function (g) {
					return _Utils_cmp(
						xOf(g.gY),
						xOf(g.f1)) < 1;
				},
				enabled)),
		fz: $elm$core$List$length(
			$elm$core$List$filter$(
				function (i) {
					return !$elm$core$Dict$member$(i, declaredSet);
				},
				referenced))
	};
};
var $author$project$Mario$Dashboard$Topology$groupColor = function (group) {
	switch (group) {
		case 0:
			return '#7f95cc';
		case 1:
			return '#4fd6e0';
		case 2:
			return '#f0715a';
		case 3:
			return '#ffb23f';
		case 4:
			return '#a99bf5';
		case 5:
			return '#f4ead6';
		case 6:
			return '#ffb23f';
		case 7:
			return '#a99bf5';
		default:
			return '#9db2d8';
	}
};
var $author$project$Mario$Dashboard$Slots$groupLabel = function (group) {
	switch (group) {
		case 0:
			return 'Combat sensors';
		case 1:
			return 'Our ship id (5 bits)';
		case 2:
			return 'Their ship id (5 bits)';
		case 3:
			return 'Previous controls (5)';
		case 4:
			return 'Previous memory (8)';
		case 5:
			return 'Bias';
		case 6:
			return 'Control outputs (5)';
		case 7:
			return 'Memory outputs (8)';
		default:
			return 'Hidden';
	}
};
var $author$project$Mario$Dashboard$Topology$viewBands = function (lay) {
	return $elm$core$List$concatMap$(
		function (_v0) {
			var group = _v0.a;
			var lo = _v0.b;
			var hi = _v0.c;
			var isOutput = (group === 6) || (group === 7);
			var x = isOutput ? ($author$project$Mario$Dashboard$Topology$outputX + 112) : 10;
			var caption = $author$project$Mario$Dashboard$Slots$groupLabel(group);
			var fits = _Utils_cmp(
				hi - lo,
				$elm$core$String$length(caption) * 5.0) > 0;
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
								$elm$core$String$fromFloat(lo - 4)),
								$elm$svg$Svg$Attributes$y2(
								$elm$core$String$fromFloat(hi + 4)),
								$elm$svg$Svg$Attributes$stroke(
								$author$project$Mario$Dashboard$Topology$groupColor(group)),
								$elm$svg$Svg$Attributes$strokeWidth('2'),
								$elm$svg$Svg$Attributes$strokeOpacity('0.5')
							]),
						_List_Nil)
					]),
				fits ? _List_fromArray(
					[
						A2(
						$elm$svg$Svg$text_,
						_List_fromArray(
							[
								$elm$svg$Svg$Attributes$x(
								$elm$core$String$fromFloat(x + 5)),
								$elm$svg$Svg$Attributes$y(
								$elm$core$String$fromFloat((lo + hi) / 2)),
								$elm$svg$Svg$Attributes$fontSize('9'),
								$elm$svg$Svg$Attributes$fill(
								$author$project$Mario$Dashboard$Topology$groupColor(group)),
								$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif'),
								$elm$svg$Svg$Attributes$transform(
								'rotate(-90 ' + ($elm$core$String$fromFloat(x + 5) + (' ' + ($elm$core$String$fromFloat((lo + hi) / 2) + ')')))),
								$elm$svg$Svg$Attributes$textAnchor('middle')
							]),
						_List_fromArray(
							[
								$elm$svg$Svg$text(caption)
							]))
					]) : _List_Nil);
		},
		lay.dC);
};
var $elm$core$Maybe$map2$ = function (func, ma, mb) {
	if (ma.$ === 1) {
		return $elm$core$Maybe$Nothing;
	} else {
		var a = ma.a;
		if (mb.$ === 1) {
			return $elm$core$Maybe$Nothing;
		} else {
			var b = mb.a;
			return $elm$core$Maybe$Just(
				A2(func, a, b));
		}
	}
};
var $elm$core$Maybe$map2 = F3($elm$core$Maybe$map2$);
var $elm$svg$Svg$Attributes$markerEnd = _VirtualDom_attribute('marker-end');
var $author$project$Mario$Dashboard$Topology$pt$ = function (x, y) {
	return $elm$core$String$fromFloat(x) + (' ' + $elm$core$String$fromFloat(y));
};
var $author$project$Mario$Dashboard$Topology$pt = F2($author$project$Mario$Dashboard$Topology$pt$);
var $author$project$Mario$Dashboard$Topology$viewEdges$ = function (config, lay, summary, genome) {
	return $elm$core$List$map$(
		function (_v0) {
			var gene = _v0.a;
			var from = _v0.b;
			var to = _v0.c;
			var touched = function () {
				var _v2 = config.i4;
				if (_v2.$ === 1) {
					return true;
				} else {
					var id = _v2.a;
					return _Utils_eq(gene.f1, id) || _Utils_eq(gene.gY, id);
				}
			}();
			var strength = $elm$core$Basics$abs(gene.g2) / summary.d3;
			var recurrent = _Utils_cmp(to.L, from.L) < 1;
			var dx = (to.L - from.L) * 0.45;
			var path = recurrent ? ('M ' + ($author$project$Mario$Dashboard$Topology$pt$(from.L, from.ap) + (' C ' + ($author$project$Mario$Dashboard$Topology$pt$(from.L + 70, from.ap - 34) + (', ' + ($author$project$Mario$Dashboard$Topology$pt$(to.L - 70, to.ap - 34) + (', ' + $author$project$Mario$Dashboard$Topology$pt$(to.L, to.ap)))))))) : ('M ' + ($author$project$Mario$Dashboard$Topology$pt$(from.L, from.ap) + (' C ' + ($author$project$Mario$Dashboard$Topology$pt$(from.L + dx, from.ap) + (', ' + ($author$project$Mario$Dashboard$Topology$pt$(to.L - dx, to.ap) + (', ' + $author$project$Mario$Dashboard$Topology$pt$(to.L, to.ap))))))));
			var color = (!gene.fX) ? '#56618a' : ((gene.g2 >= 0) ? '#4fd6e0' : '#f0715a');
			var baseOpacity = 0.12 + (0.55 * strength);
			var opacity = function () {
				var _v1 = config.i4;
				if (_v1.$ === 1) {
					return baseOpacity;
				} else {
					return touched ? $elm$core$Basics$min$(1, baseOpacity + 0.35) : 0.05;
				}
			}();
			return A2(
				$elm$svg$Svg$path,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$d(path),
						$elm$svg$Svg$Attributes$fill('none'),
						$elm$svg$Svg$Attributes$stroke(color),
						$elm$svg$Svg$Attributes$strokeWidth(
						$elm$core$String$fromFloat(0.5 + (1.8 * strength))),
						$elm$svg$Svg$Attributes$strokeOpacity(
						$elm$core$String$fromFloat(opacity)),
						$elm$svg$Svg$Attributes$strokeDasharray(
						gene.fX ? 'none' : '3 3'),
						$elm$svg$Svg$Attributes$markerEnd(
						recurrent ? 'url(#mario-recurrent-arrow)' : 'none')
					]),
				_List_Nil);
		},
		$elm$core$List$filterMap$(
			function (gene) {
				return $elm$core$Maybe$map2$(
					F2(
						function (a, b) {
							return _Utils_Tuple3(gene, a, b);
						}),
					$elm$core$Dict$get$(gene.f1, lay.cz),
					$elm$core$Dict$get$(gene.gY, lay.cz));
			},
			genome.ke));
};
var $author$project$Mario$Dashboard$Topology$viewEdges = F4($author$project$Mario$Dashboard$Topology$viewEdges$);
var $author$project$Mario$Dashboard$Topology$viewKey = A2(
	$elm$html$Html$div,
	_List_fromArray(
		[
			$elm$html$Html$Attributes$class('topo-key')
		]),
	_Utils_ap(
		$elm$core$List$map$(
			function (group) {
				return A2(
					$elm$html$Html$span,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('swatch'),
									A2(
									$elm$html$Html$Attributes$style,
									'background',
									$author$project$Mario$Dashboard$Topology$groupColor(group))
								]),
							_List_Nil),
							$elm$html$Html$text(
							$author$project$Mario$Dashboard$Slots$groupLabel(group))
						]));
			},
			_List_fromArray(
				[0, 1, 2, 3, 4, 5, 8])),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#4fd6e0')
							]),
						_List_Nil),
						$elm$html$Html$text('positive weight')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#f0715a')
							]),
						_List_Nil),
						$elm$html$Html$text('negative weight')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('swatch'),
								A2($elm$html$Html$Attributes$style, 'background', '#56618a')
							]),
						_List_Nil),
						$elm$html$Html$text('disabled gene (dashed)')
					])),
				A2(
				$elm$html$Html$span,
				_List_Nil,
				_List_fromArray(
					[
						$elm$html$Html$text('Bowed curves are recurrent links.')
					]))
			])));
var $author$project$Mario$Dashboard$Slots$Slot$ = function (id, group, _short, detail) {
	return {fQ: detail, f5: group, e1: id, gO: _short};
};
var $author$project$Mario$Dashboard$Slots$Slot = F4($author$project$Mario$Dashboard$Slots$Slot$);
var $author$project$Mario$Dashboard$Slots$controlNames = _List_fromArray(
	['left', 'right', 'thrust', 'weapon', 'special']);
var $author$project$Mario$Dashboard$Slots$nth$ = function (index, list, fallback) {
	return $elm$core$Maybe$withDefault$(
		fallback,
		$elm$core$List$head(
			$elm$core$List$drop$(index, list)));
};
var $author$project$Mario$Dashboard$Slots$nth = F3($author$project$Mario$Dashboard$Slots$nth$);
var $author$project$Mario$Dashboard$Slots$abilityBase = 44;
var $author$project$Mario$Dashboard$Slots$abilityBits = 7;
var $author$project$Mario$Dashboard$Slots$abilityInfo = function (offset) {
	var side = (_Utils_cmp(offset, $author$project$Mario$Dashboard$Slots$abilityBits) < 0) ? 'our ship' : 'the opponent';
	var prefix = (_Utils_cmp(offset, $author$project$Mario$Dashboard$Slots$abilityBits) < 0) ? 'us ' : 'them ';
	var _v0 = function () {
		var _v1 = A2($elm$core$Basics$modBy, $author$project$Mario$Dashboard$Slots$abilityBits, offset);
		switch (_v1) {
			case 0:
				return _Utils_Tuple2('seek wpn', 'primary weapon homes on its target');
			case 1:
				return _Utils_Tuple2('seek spec', 'special ability homes on its target');
			case 2:
				return _Utils_Tuple2('instant wpn', 'weapon hits the instant it is fired, with no travel time');
			case 3:
				return _Utils_Tuple2('fire fore', 'weapon fires forward');
			case 4:
				return _Utils_Tuple2('fire right', 'weapon fires to the right');
			case 5:
				return _Utils_Tuple2('fire aft', 'weapon fires backwards');
			default:
				return _Utils_Tuple2('fire left', 'weapon fires to the left');
		}
	}();
	var _short = _v0.a;
	var detail = _v0.b;
	return _Utils_Tuple2(
		_Utils_ap(prefix, _short),
		'1 when ' + (side + ('\'s ' + (detail + '.'))));
};
var $author$project$Mario$Dashboard$Slots$plainSensor = function (id) {
	switch (id) {
		case 0:
			return _Utils_Tuple2('our energy', 'Our battery charge divided by our maximum, 0 to 1.');
		case 1:
			return _Utils_Tuple2('our crew', 'Our surviving crew divided by our maximum crew, 0 to 1.');
		case 2:
			return _Utils_Tuple2('facing cos', 'Cosine of the direction our ship points.');
		case 3:
			return _Utils_Tuple2('facing sin', 'Sine of the direction our ship points.');
		case 4:
			return _Utils_Tuple2('our speed', 'Our speed divided by our maximum thrust speed, 0 to 1.');
		case 5:
			return _Utils_Tuple2('drift cos', 'Cosine of the angle between where we are travelling and where we point.');
		case 6:
			return _Utils_Tuple2('drift sin', 'Sine of the angle between where we are travelling and where we point.');
		case 7:
			return _Utils_Tuple2('weapon ready', '1 when the primary weapon cooldown has expired.');
		case 8:
			return _Utils_Tuple2('special ready', '1 when the special ability cooldown has expired.');
		case 9:
			return _Utils_Tuple2('turn ready', '1 when the turn cooldown has expired.');
		case 10:
			return _Utils_Tuple2('thrust ready', '1 when the thrust cooldown has expired.');
		case 11:
			return _Utils_Tuple2('at limit', '1 when we are already at our speed limit. This is the predicate the cyborg coasts on, which the speed ratio at slot 4 cannot express.');
		case 12:
			return _Utils_Tuple2('beyond limit', '1 when we are travelling faster than our own limit, usually after a gravity slingshot.');
		case 13:
			return _Utils_Tuple2('in gravity', '1 while the planet\'s gravity well has hold of us.');
		case 14:
			return _Utils_Tuple2('uses inertia', '1 for a hull that accelerates gradually rather than snapping to full speed.');
		case 15:
			return _Utils_Tuple2('ultra', '1 for a hull that snaps to full speed and is at least moderately agile. The cyborg treats these differently around gravity and homing missiles.');
		case 16:
			return _Utils_Tuple2('can pay wpn', '1 when we hold at least the energy one shot costs.');
		case 17:
			return _Utils_Tuple2('can pay spec', '1 when we hold at least the energy one special costs.');
		case 18:
			return _Utils_Tuple2('approach fuel', 'How many turns of special the energy we hold would pay for, over 64. This is the budget Umgah plans its approach with.');
		case 19:
			return _Utils_Tuple2('special timer', 'The special cooldown itself over 64, not just whether it expired. Chenjesu fires on exactly one tick remaining.');
		case 20:
			return _Utils_Tuple2('our hull mass', 'Our hull\'s inertial mass over twice the ordinary maximum, so a transformed hull reads above one half.');
		case 21:
			return _Utils_Tuple2('foe dx', 'Horizontal offset to the opponent across the wrapped arena, scaled by half the arena width.');
		case 22:
			return _Utils_Tuple2('foe dy', 'Vertical offset to the opponent across the wrapped arena, scaled by half the arena height.');
		case 23:
			return _Utils_Tuple2('foe range', 'Straight-line distance to the opponent, scaled by 4000 world units and clamped.');
		case 24:
			return _Utils_Tuple2('closing rate', 'How fast the gap to the opponent is shrinking, scaled by 200 and clamped.');
		case 25:
			return _Utils_Tuple2('foe facing cos', 'Cosine of the opponent\'s facing relative to ours.');
		case 26:
			return _Utils_Tuple2('foe facing sin', 'Sine of the opponent\'s facing relative to ours.');
		case 27:
			return _Utils_Tuple2('foe speed', 'Opponent speed divided by their maximum thrust speed.');
		case 28:
			return _Utils_Tuple2('aim error', 'Signed turn error between our facing and the bearing to the opponent, in facing steps over 8.');
		case 29:
			return _Utils_Tuple2('foe hull mass', 'The opponent hull\'s inertial mass over twice the ordinary maximum, so a transformed hull reads above one half.');
		case 30:
			return _Utils_Tuple2('foe cloak', '1 while the opponent\'s hull is drawn cloaked, which is what widens the cyborg\'s aiming margin.');
		case 31:
			return _Utils_Tuple2('we cloak', '1 while our ship is cloaked.');
		case 32:
			return _Utils_Tuple2('foe energy', 'Opponent battery charge divided by their maximum. Deliberately more than the cyborg reads.');
		case 33:
			return _Utils_Tuple2('foe crew', 'Opponent crew divided by their maximum crew. Deliberately more than the cyborg reads.');
		case 34:
			return _Utils_Tuple2('we can fire', '1 when a shot fired right now would connect, by the cyborg\'s own firing test.');
		case 35:
			return _Utils_Tuple2('we close in', 'Urgency of closing to within three quarters of our own weapon range.');
		case 36:
			return _Utils_Tuple2('they can fire', '1 when a shot the opponent fires now would connect with us. Against a missile hull this is more than the cyborg is told.');
		case 37:
			return _Utils_Tuple2('they close in', 'Urgency of the opponent closing to within three quarters of their weapon range.');
		case 38:
			return _Utils_Tuple2('they hit instantly', '1 when the opponent\'s weapon hits the instant it is fired. This says whether the two slots before it are what the cyborg also sees.');
		case 39:
			return _Utils_Tuple2('our range', 'Our weapon\'s engagement range over 4000 world units.');
		case 40:
			return _Utils_Tuple2('their range', 'The opponent\'s engagement range over 4000 world units.');
		case 41:
			return _Utils_Tuple2('our agility', 'Our maneuverability rating over 150, the fast-ship mark.');
		case 42:
			return _Utils_Tuple2('their agility', 'The opponent\'s maneuverability rating over 150.');
		case 43:
			return _Utils_Tuple2('thrust edge', 'Our maximum thrust minus theirs, over 64. The raw comparison the cyborg makes, which the two speed ratios destroy.');
		case 58:
			return _Utils_Tuple2('planet dx', 'Horizontal offset to the planet, scaled by 4000 world units and clamped.');
		case 59:
			return _Utils_Tuple2('planet dy', 'Vertical offset to the planet, scaled by 4000 world units and clamped.');
		case 60:
			return _Utils_Tuple2('planet impact', 'Urgency of a predicted collision with the planet, from the cyborg\'s own three-margin gravity test. 0 when no impact is predicted.');
		case 85:
			return _Utils_Tuple2('crew dx', 'Horizontal offset to the nearest floating crew pod, scaled by half the arena width.');
		case 86:
			return _Utils_Tuple2('crew dy', 'Vertical offset to the nearest floating crew pod, scaled by half the arena height.');
		case 87:
			return _Utils_Tuple2('crew urgency', 'Urgency of reaching the nearest floating crew pod. 0 when there is none.');
		case 88:
			return _Utils_Tuple2('crew targeted', '1 when our ship is already chasing that crew pod.');
		case 89:
			return _Utils_Tuple2('rock dx', 'Horizontal offset to the nearest neutral body, an asteroid or debris, scaled by 4000 world units.');
		case 90:
			return _Utils_Tuple2('rock dy', 'Vertical offset to the nearest neutral body, scaled by 4000 world units.');
		case 91:
			return _Utils_Tuple2('rock urgency', 'Urgency of reaching the nearest neutral body. 0 when there is none.');
		case 92:
			return _Utils_Tuple2('constant 1', 'The constant sensor the encoder already emits. Always 1. Distinct from the extra bias input at node 116.');
		default:
			return _Utils_Tuple2(
				'sensor ' + $elm$core$String$fromInt(id),
				'Combat sensor ' + ($elm$core$String$fromInt(id) + '.'));
	}
};
var $author$project$Mario$Dashboard$Slots$threatBase = 61;
var $author$project$Mario$Dashboard$Slots$threatInfo$ = function (rank, field) {
	var rankName = 'threat ' + $elm$core$String$fromInt(rank);
	var _v0 = function () {
		switch (field) {
			case 0:
				return _Utils_Tuple2('urgency', 'Urgency of the predicted impact. 0 when this projectile is not predicted to reach us, or when there is no such projectile.');
			case 1:
				return _Utils_Tuple2('travel cos', 'Cosine of the direction it is travelling, relative to where we point.');
			case 2:
				return _Utils_Tuple2('travel sin', 'Sine of the direction it is travelling, relative to where we point.');
			case 3:
				return _Utils_Tuple2('closing', 'Cosine of the angle between its travel direction and its bearing to us. Near 1 means it is coming straight at us.');
			case 4:
				return _Utils_Tuple2('seeking', '1 when it homes, worked out from the ability of the ship that launched it.');
			case 5:
				return _Utils_Tuple2('finite life', '1 when it expires on a timer rather than persisting.');
			case 6:
				return _Utils_Tuple2('damage', 'Its mass, which is the crew it would cost us, over our maximum crew.');
			default:
				return _Utils_Tuple2('life left', 'How much of its flight time remains, over 64.');
		}
	}();
	var _short = _v0.a;
	var detail = _v0.b;
	return _Utils_Tuple2(
		rankName + (' ' + _short),
		'Ranked hostile projectile ' + ($elm$core$String$fromInt(rank) + (', soonest predicted impact first. ' + detail)));
};
var $author$project$Mario$Dashboard$Slots$threatInfo = F2($author$project$Mario$Dashboard$Slots$threatInfo$);
var $author$project$Mario$Dashboard$Slots$threatSlots = 3;
var $author$project$Mario$Dashboard$Slots$threatWidth = 8;
var $author$project$Mario$Dashboard$Slots$sensorInfo = function (id) {
	return ((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$abilityBase) > -1) && (_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$abilityBase + (2 * $author$project$Mario$Dashboard$Slots$abilityBits)) < 0)) ? $author$project$Mario$Dashboard$Slots$abilityInfo(id - $author$project$Mario$Dashboard$Slots$abilityBase) : (((_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$threatBase) > -1) && (_Utils_cmp(id, $author$project$Mario$Dashboard$Slots$threatBase + ($author$project$Mario$Dashboard$Slots$threatSlots * $author$project$Mario$Dashboard$Slots$threatWidth)) < 0)) ? $author$project$Mario$Dashboard$Slots$threatInfo$(
		((id - $author$project$Mario$Dashboard$Slots$threatBase) / $author$project$Mario$Dashboard$Slots$threatWidth) | 0,
		A2($elm$core$Basics$modBy, $author$project$Mario$Dashboard$Slots$threatWidth, id - $author$project$Mario$Dashboard$Slots$threatBase)) : $author$project$Mario$Dashboard$Slots$plainSensor(id));
};
var $author$project$Mario$Dashboard$Slots$slot = function (id) {
	var group = $author$project$Mario$Dashboard$Slots$groupOf(id);
	switch (group) {
		case 0:
			var _v1 = $author$project$Mario$Dashboard$Slots$sensorInfo(id);
			var _short = _v1.a;
			var detail = _v1.b;
			return $author$project$Mario$Dashboard$Slots$Slot$(id, group, _short, detail);
		case 1:
			var bit = id - $author$project$Mario$Dashboard$Slots$sensorCount;
			return $author$project$Mario$Dashboard$Slots$Slot$(
				id,
				group,
				'us b' + $elm$core$String$fromInt(bit),
				'Bit ' + ($elm$core$String$fromInt(bit) + (' (value ' + ($elm$core$String$fromInt(
					A2($elm$core$Basics$pow, 2, bit)) + ') of our ship\'s index in the 25-ship roster, least significant bit first.'))));
		case 2:
			var bit = id - ($author$project$Mario$Dashboard$Slots$sensorCount + $author$project$Mario$Dashboard$Slots$shipBits);
			return $author$project$Mario$Dashboard$Slots$Slot$(
				id,
				group,
				'them b' + $elm$core$String$fromInt(bit),
				'Bit ' + ($elm$core$String$fromInt(bit) + (' (value ' + ($elm$core$String$fromInt(
					A2($elm$core$Basics$pow, 2, bit)) + ') of the opponent ship\'s index in the 25-ship roster, least significant bit first.'))));
		case 3:
			var idx = id - $author$project$Mario$Dashboard$Slots$observationCount;
			var name = $author$project$Mario$Dashboard$Slots$nth$(idx, $author$project$Mario$Dashboard$Slots$controlNames, 'control');
			return $author$project$Mario$Dashboard$Slots$Slot$(id, group, 'prev ' + name, 'The ' + (name + ' control bit actually applied on the previous step, 1 or 0. This is the applied bit, not the raw output, so the left/right conflict rule is already resolved.'));
		case 4:
			var channel = id - ($author$project$Mario$Dashboard$Slots$observationCount + $author$project$Mario$Dashboard$Slots$controlCount);
			return $author$project$Mario$Dashboard$Slots$Slot$(
				id,
				group,
				'prev mem ' + $elm$core$String$fromInt(channel),
				'Memory channel ' + ($elm$core$String$fromInt(channel) + ' as emitted on the previous step, fed straight back in. Bounded to -1..1.'));
		case 5:
			return $author$project$Mario$Dashboard$Slots$Slot$(id, group, 'bias', 'The extra bias input. Always exactly 1, on every step of every episode.');
		case 6:
			var idx = id - $author$project$Mario$Dashboard$Slots$outputFirst;
			var name = $author$project$Mario$Dashboard$Slots$nth$(idx, $author$project$Mario$Dashboard$Slots$controlNames, 'control');
			return $author$project$Mario$Dashboard$Slots$Slot$(id, group, name, 'Control output for ' + (name + '. Applied when greater than zero. If left and right are both positive the ship does not turn.'));
		case 7:
			var channel = id - ($author$project$Mario$Dashboard$Slots$outputFirst + $author$project$Mario$Dashboard$Slots$controlCount);
			return $author$project$Mario$Dashboard$Slots$Slot$(
				id,
				group,
				'mem ' + $elm$core$String$fromInt(channel),
				'Memory output channel ' + ($elm$core$String$fromInt(channel) + ('. Bounded, stored, and fed back in as input ' + ($elm$core$String$fromInt(($author$project$Mario$Dashboard$Slots$observationCount + $author$project$Mario$Dashboard$Slots$controlCount) + channel) + ' on the next step.'))));
		default:
			return $author$project$Mario$Dashboard$Slots$Slot$(
				id,
				group,
				'h' + $elm$core$String$fromInt(id),
				'Hidden node ' + ($elm$core$String$fromInt(id) + ', added by a structural mutation.'));
	}
};
var $author$project$Mario$Dashboard$Topology$viewNode$ = function (config, crowded, placed) {
	var radius = function () {
		var _v0 = placed.f5;
		switch (_v0) {
			case 8:
				return 4;
			case 6:
				return 4.5;
			case 7:
				return 4.5;
			default:
				return 3.2;
		}
	}();
	var isSelected = _Utils_eq(
		config.i4,
		$elm$core$Maybe$Just(placed.e1));
	var isOutput = (placed.f5 === 6) || (placed.f5 === 7);
	var info = $author$project$Mario$Dashboard$Slots$slot(placed.e1);
	var labelNode = (placed.f5 === 8) ? (crowded ? _List_Nil : _List_fromArray(
		[
			A2(
			$elm$svg$Svg$text_,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$x(
					$elm$core$String$fromFloat(placed.L)),
					$elm$svg$Svg$Attributes$y(
					$elm$core$String$fromFloat(placed.ap - 7)),
					$elm$svg$Svg$Attributes$fontSize('7.5'),
					$elm$svg$Svg$Attributes$fill('#7483a6'),
					$elm$svg$Svg$Attributes$textAnchor('middle'),
					$elm$svg$Svg$Attributes$fontFamily('ui-monospace, Menlo, Consolas, monospace')
				]),
			_List_fromArray(
				[
					$elm$svg$Svg$text(
					$elm$core$String$fromInt(placed.e1))
				]))
		])) : _List_fromArray(
		[
			A2(
			$elm$svg$Svg$text_,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$x(
					$elm$core$String$fromFloat(
						isOutput ? (placed.L + 9) : (placed.L - 9))),
					$elm$svg$Svg$Attributes$y(
					$elm$core$String$fromFloat(placed.ap + 3)),
					$elm$svg$Svg$Attributes$fontSize('8.5'),
					$elm$svg$Svg$Attributes$fill(
					isSelected ? '#f4ead6' : '#98a6c7'),
					$elm$svg$Svg$Attributes$textAnchor(
					isOutput ? 'start' : 'end'),
					$elm$svg$Svg$Attributes$fontFamily('ui-sans-serif, system-ui, sans-serif')
				]),
			_List_fromArray(
				[
					$elm$svg$Svg$text(info.gO)
				]))
		]);
	var color = $author$project$Mario$Dashboard$Topology$groupColor(placed.f5);
	return _Utils_ap(
		labelNode,
		_List_fromArray(
			[
				A2(
				$elm$svg$Svg$circle,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$cx(
						$elm$core$String$fromFloat(placed.L)),
						$elm$svg$Svg$Attributes$cy(
						$elm$core$String$fromFloat(placed.ap)),
						$elm$svg$Svg$Attributes$r(
						$elm$core$String$fromFloat(radius)),
						$elm$svg$Svg$Attributes$fill(
						placed.c1 ? color : '#05070f'),
						$elm$svg$Svg$Attributes$stroke(
						isSelected ? '#f4ead6' : color),
						$elm$svg$Svg$Attributes$strokeWidth(
						isSelected ? '2' : '1'),
						$elm$svg$Svg$Attributes$strokeDasharray(
						placed.c1 ? 'none' : '2 2')
					]),
				_List_Nil),
				A2(
				$elm$svg$Svg$circle,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$cx(
						$elm$core$String$fromFloat(placed.L)),
						$elm$svg$Svg$Attributes$cy(
						$elm$core$String$fromFloat(placed.ap)),
						$elm$svg$Svg$Attributes$r('8'),
						$elm$svg$Svg$Attributes$fill('transparent'),
						$elm$svg$Svg$Events$onMouseOver(
						config.iI(placed.e1)),
						$elm$svg$Svg$Events$onClick(
						config.iI(placed.e1))
					]),
				_List_Nil)
			]));
};
var $author$project$Mario$Dashboard$Topology$viewNode = F3($author$project$Mario$Dashboard$Topology$viewNode$);
var $elm$html$Html$br = _VirtualDom_node('br');
var $author$project$Mario$Dashboard$Format$signedWeight = function (w) {
	return (w >= 0) ? ('+' + $author$project$Mario$Dashboard$Format$decimal$(3, w)) : $author$project$Mario$Dashboard$Format$decimal$(3, w);
};
var $author$project$Mario$Dashboard$Topology$strongestNote$ = function (incoming, outgoing) {
	var strongest = $elm$core$List$head(
		A2(
			$elm$core$List$sortBy,
			function (g) {
				return -$elm$core$Basics$abs(g.g2);
			},
			$elm$core$List$filter$(
				function ($) {
					return $.fX;
				},
				_Utils_ap(incoming, outgoing))));
	if (strongest.$ === 1) {
		return ' No enabled connection touches this node, so it contributes nothing.';
	} else {
		var g = strongest.a;
		return ' Strongest link: ' + ($elm$core$String$fromInt(g.f1) + (' \u2192 ' + ($elm$core$String$fromInt(g.gY) + (' at ' + ($author$project$Mario$Dashboard$Format$signedWeight(g.g2) + '.')))));
	}
};
var $author$project$Mario$Dashboard$Topology$strongestNote = F2($author$project$Mario$Dashboard$Topology$strongestNote$);
var $author$project$Mario$Dashboard$Topology$viewReadout$ = function (config, genome, summary) {
	var base = $elm$html$Html$div(
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('topo-readout'),
				$elm$html$Html$Attributes$id(config.dM)
			]));
	var _v0 = config.i4;
	if (_v0.$ === 1) {
		return base(
			_List_fromArray(
				[
					$elm$html$Html$text(
					$elm$core$String$fromInt(summary.iE) + (' nodes (' + ($elm$core$String$fromInt(summary.dS) + (' hidden, evolved), ' + ($elm$core$String$fromInt(summary.fX) + (' enabled connections of which ' + ($elm$core$String$fromInt(summary.eo) + (' are recurrent, ' + ($elm$core$String$fromInt(summary.dN) + ' disabled. Hover, tap, or focus the graph and use the arrow keys to inspect a node.')))))))))
				]));
	} else {
		var id = _v0.a;
		var outgoing = $elm$core$List$filter$(
			function (g) {
				return _Utils_eq(g.f1, id);
			},
			genome.ke);
		var info = $author$project$Mario$Dashboard$Slots$slot(id);
		var incoming = $elm$core$List$filter$(
			function (g) {
				return _Utils_eq(g.gY, id);
			},
			genome.ke);
		var describe = F2(
			function (label, list) {
				return label + (' ' + ($elm$core$String$fromInt(
					$elm$core$List$length(
						$elm$core$List$filter$(
							function ($) {
								return $.fX;
							},
							list))) + (' enabled' + ((_Utils_cmp(
					$elm$core$List$length(list),
					$elm$core$List$length(
						$elm$core$List$filter$(
							function ($) {
								return $.fX;
							},
							list))) > 0) ? (', ' + ($elm$core$String$fromInt(
					$elm$core$List$length(list) - $elm$core$List$length(
						$elm$core$List$filter$(
							function ($) {
								return $.fX;
							},
							list))) + ' disabled')) : ''))));
			});
		return base(
			_List_fromArray(
				[
					A2(
					$elm$html$Html$b,
					_List_Nil,
					_List_fromArray(
						[
							$elm$html$Html$text(
							'node ' + ($elm$core$String$fromInt(id) + (' \u00B7 ' + info.gO)))
						])),
					$elm$html$Html$text(
					' \u00B7 ' + $author$project$Mario$Dashboard$Slots$groupLabel(info.f5)),
					A2($elm$html$Html$br, _List_Nil, _List_Nil),
					$elm$html$Html$text(info.fQ),
					A2($elm$html$Html$br, _List_Nil, _List_Nil),
					$elm$html$Html$text(
					A2(describe, 'In:', incoming) + ('. ' + (A2(describe, 'Out:', outgoing) + '.'))),
					$elm$html$Html$text(
					$author$project$Mario$Dashboard$Topology$strongestNote$(incoming, outgoing))
				]));
	}
};
var $author$project$Mario$Dashboard$Topology$viewReadout = F3($author$project$Mario$Dashboard$Topology$viewReadout$);
var $author$project$Mario$Dashboard$Topology$view$ = function (config, genome) {
	var summary = $author$project$Mario$Dashboard$Topology$summarize(genome);
	var lay = $author$project$Mario$Dashboard$Topology$layout(genome);
	var ids = $elm$core$List$sort(
		$elm$core$List$map$(
			function ($) {
				return $.e1;
			},
			lay.dm));
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('topo-wrap')
					]),
				_List_fromArray(
					[
						A2(
						$elm$svg$Svg$svg,
						_List_fromArray(
							[
								$elm$svg$Svg$Attributes$class('topo-svg'),
								$elm$svg$Svg$Attributes$viewBox(
								'0 0 ' + ($elm$core$String$fromFloat($author$project$Mario$Dashboard$Topology$userWidth) + (' ' + $elm$core$String$fromFloat(lay.f8)))),
								A2($elm$html$Html$Attributes$attribute, 'role', 'group'),
								A2($elm$html$Html$Attributes$attribute, 'tabindex', '0'),
								A2(
								$elm$html$Html$Attributes$attribute,
								'aria-label',
								'Champion network graph with ' + ($elm$core$String$fromInt(summary.iE) + (' nodes and ' + ($elm$core$String$fromInt(summary.fX) + ' enabled connections. Focus this graph and use the arrow keys to step through nodes.')))),
								A2($elm$html$Html$Attributes$attribute, 'aria-describedby', config.dM),
								$elm$html$Html$Events$preventDefaultOn$(
								'keydown',
								$author$project$Mario$Dashboard$Topology$arrowDecoder$(config, ids))
							]),
						A2(
							$elm$core$List$cons,
							$author$project$Mario$Dashboard$Topology$defs,
							_Utils_ap(
								$author$project$Mario$Dashboard$Topology$viewBands(lay),
								_Utils_ap(
									$author$project$Mario$Dashboard$Topology$viewEdges$(config, lay, summary, genome),
									$elm$core$List$concatMap$(
										A2($author$project$Mario$Dashboard$Topology$viewNode, config, lay.dJ),
										lay.dm)))))
					])),
				$author$project$Mario$Dashboard$Topology$viewReadout$(config, genome, summary),
				$author$project$Mario$Dashboard$Topology$viewKey
			]));
};
var $author$project$Mario$Dashboard$Topology$view = F2($author$project$Mario$Dashboard$Topology$view$);
var $author$project$Mario$Dashboard$viewTopology$ = function (tips, model, status) {
	var mismatch = function () {
		var _v4 = _Utils_Tuple2(
			$elm$core$Maybe$andThen$(
				function ($) {
					return $.dF;
				},
				model.cE),
			status.eJ.e1);
		if ((!_v4.a.$) && (!_v4.b.$)) {
			var drawn = _v4.a.a;
			var current = _v4.b.a;
			return !_Utils_eq(drawn, current);
		} else {
			return false;
		}
	}();
	var body = function () {
		var _v0 = _Utils_Tuple2(model.cE, model.cF);
		if (!_v0.a.$) {
			var network = _v0.a.a;
			return ($elm$core$List$isEmpty(network.f4.iE) && $elm$core$List$isEmpty(network.f4.ke)) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('placeholder')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$strong,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('Empty genome')
							])),
						A2(
						$elm$html$Html$span,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('The network endpoint answered, but there is no champion genome to draw yet.')
							]))
					])) : A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						mismatch ? A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('banner banner-warn')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$div,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										'This graph is champion ' + ($author$project$Mario$Dashboard$Format$shortId(
											$elm$core$Maybe$withDefault$('', network.dF)) + (', but the current champion is ' + ($author$project$Mario$Dashboard$Format$shortId(
											$elm$core$Maybe$withDefault$('', status.eJ.e1)) + '. Refresh to fetch the current genome.'))))
									])),
								A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('banner-actions')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$button,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('btn btn-small'),
												$elm$html$Html$Events$onClick($author$project$Mario$Dashboard$RefreshNow)
											]),
										_List_fromArray(
											[
												$elm$html$Html$text('Refresh')
											]))
									]))
							])) : $elm$html$Html$text(''),
						$author$project$Mario$Dashboard$Topology$view$(
						{dM: 'readout-topology', iH: $author$project$Mario$Dashboard$NodeClear, iI: $author$project$Mario$Dashboard$NodeSelect, i4: model.cH},
						network.f4)
					]));
		} else {
			if (!_v0.b.$) {
				var _v1 = _v0.a;
				var reason = _v0.b.a;
				return A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('placeholder')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$strong,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Network unavailable')
								])),
							A2(
							$elm$html$Html$span,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Could not read ' + ($author$project$Mario$Dashboard$networkUrl + (': ' + (reason + '.'))))
								])),
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('btn btn-small'),
									$elm$html$Html$Events$onClick($author$project$Mario$Dashboard$RefreshNow)
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Retry')
								]))
						]));
			} else {
				var _v2 = _v0.a;
				var _v3 = _v0.b;
				return A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('placeholder')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$strong,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Loading genome')
								])),
							A2(
							$elm$html$Html$span,
							_List_Nil,
							_List_fromArray(
								[
									$elm$html$Html$text('Fetching the champion network.')
								]))
						]));
			}
		}
	}();
	return $author$project$Mario$Dashboard$foldPanel$(
		tips,
		$author$project$Mario$Dashboard$Copy$topology,
		'Champion network topology',
		$elm$core$String$fromInt($author$project$Mario$Dashboard$Slots$inputCount) + (' inputs \u2192 evolved hidden nodes \u2192 ' + ($elm$core$String$fromInt($author$project$Mario$Dashboard$Slots$outputCount) + ' outputs \u00B7 open to look closer')),
		_List_fromArray(
			[body]));
};
var $author$project$Mario$Dashboard$viewTopology = F3($author$project$Mario$Dashboard$viewTopology$);
var $author$project$Mario$Dashboard$WinHover = function (a) {
	return {$: 8, a: a};
};
var $author$project$Mario$Dashboard$WinLeave = {$: 9};
var $author$project$Mario$Dashboard$Copy$winRateChart = function (scoring) {
	return A4(
		$author$project$Mario$Dashboard$Copy$t,
		'chart-winrate',
		$author$project$Mario$Dashboard$Scoring$successHeading(scoring) + ' over generations',
		'Two screening measurements, drawn so they cannot be mistaken for each other, and neither of them is gate evidence. The training line is the champion\'s own ' + ($author$project$Mario$Dashboard$Copy$rateOf(scoring) + ' on that generation\'s sampled training panel, recorded for the champion\'s member alone rather than averaged over the population. The markers are the recurring readiness probe: the trainer publishes them as the run\'s validation figure, but the probe only decides when an audit is worth spending, so a marker is never a passed gate. Both ask the same question the gate asks, on the run\'s own criterion. Every point measures the same whole board, so the only break in either line is an unmeasured generation.'),
		_List_fromArray(
			[
				_Utils_Tuple2('Denominator', 'Training: episodes on that generation\'s sampled panel for the champion\'s own member. Readiness: games in the probe\'s own batch.'),
				_Utils_Tuple2('Window', 'Per generation, whole run.'),
				_Utils_Tuple2('Source', 'Training play and the readiness probe, never averaged together. Neither is audit evidence; the gate panel above is. Unmeasured generations leave a gap rather than a zero.')
			]));
};
var $author$project$Mario$Dashboard$withNote$ = function (note, body) {
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				body,
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('prose'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '8px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(note)
					]))
			]));
};
var $author$project$Mario$Dashboard$withNote = F2($author$project$Mario$Dashboard$withNote$);
var $author$project$Mario$Dashboard$viewWinChart$ = function (tips, model, status) {
	var validation = function () {
		var base = $author$project$Mario$Dashboard$Chart$series$(
			'validation',
			'Champion readiness ' + ($author$project$Mario$Dashboard$Scoring$rateLabel(status.m) + ' (screening probe, not audit evidence)'),
			'#4fd6e0',
			$elm$core$List$map$(
				function ($) {
					return $.ly;
				},
				status.c6));
		return _Utils_update(
			base,
			{kp: true, jv: 2.4});
	}();
	var training = function () {
		var base = $author$project$Mario$Dashboard$Chart$series$(
			'training',
			'Training ' + ($author$project$Mario$Dashboard$Scoring$rateLabel(status.m) + ' (champion\'s own sampled panel this generation)'),
			'#ffb23f',
			$elm$core$List$map$(
				function ($) {
					return $.ls;
				},
				status.c6));
		return _Utils_update(
			base,
			{jv: 1.3});
	}();
	var target = $elm$core$Maybe$withDefault$(
		0.8,
		$elm$core$Maybe$map$(
			function ($) {
				return $.aJ;
			},
			status.cd));
	return $author$project$Mario$Dashboard$chartPanel$(
		tips,
		$author$project$Mario$Dashboard$Tip$detail$(
			$author$project$Mario$Dashboard$Copy$winRateChart(status.m),
			$author$project$Mario$Dashboard$Scoring$explainGate(status.m)),
		$author$project$Mario$Dashboard$Scoring$successHeading(status.m) + ' over generations',
		status,
		$author$project$Mario$Dashboard$withNote$(
			'Neither line is gate evidence. Training is the sampled panel the population was scored on; readiness is the cheap balanced probe that decides when an audit is worth spending. The gate guide is the aggregate target both are read against.',
			$author$project$Mario$Dashboard$Chart$view(
				{
					dM: 'readout-winrate',
					fW: 'The trainer publishes a history point once the first generation has been scored.',
					f$: $author$project$Mario$Dashboard$Format$percent1,
					f6: _List_fromArray(
						[
							{
							ht: '#f4ead6',
							n: 'gate ' + $author$project$Mario$Dashboard$Format$percent(target),
							r: target
						}
						]),
					f8: 240,
					f9: model.cX,
					gu: $author$project$Mario$Dashboard$WinHover,
					gv: $author$project$Mario$Dashboard$WinLeave,
					gM: _List_fromArray(
						[training, validation]),
					g$: 760,
					g6: $author$project$Mario$Dashboard$historyLabels(status),
					g7: 1,
					g8: 0,
					g9: $elm$core$List$map$(
						function (v) {
							return _Utils_Tuple2(
								v,
								$author$project$Mario$Dashboard$Format$percent(v));
						},
						_List_fromArray(
							[0, 0.25, 0.5, 0.75, 1]))
				})));
};
var $author$project$Mario$Dashboard$viewWinChart = F3($author$project$Mario$Dashboard$viewWinChart$);
var $author$project$Mario$Dashboard$viewBody = function (model) {
	var _v0 = model.aI;
	if (_v0.$ === 1) {
		return model.cM ? _List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('placeholder')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Not connected')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text(
										'The dashboard could not read ' + ($author$project$Mario$Dashboard$statusUrl + (': ' + ($elm$core$Maybe$withDefault$('unknown reason', model.bj) + '.'))))
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('No data is shown because none has ever been received in this session. Start the trainer, then retry.')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('btn btn-primary'),
										$elm$html$Html$Events$onClick($author$project$Mario$Dashboard$RefreshNow)
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Retry now')
									]))
							]))
					]))
			]) : _List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('panel')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('placeholder')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$strong,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Loading')
									])),
								A2(
								$elm$html$Html$span,
								_List_Nil,
								_List_fromArray(
									[
										$elm$html$Html$text('Waiting for the first status snapshot from the local trainer.')
									]))
							]))
					]))
			]);
	} else {
		var status = _v0.a;
		var tips = $author$project$Mario$Dashboard$tipHandlers(model);
		return _List_fromArray(
			[
				$author$project$Mario$Dashboard$band$(
				'Am I winning?',
				'The one graded question, and the trend behind it.',
				_List_fromArray(
					[
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewGate$(tips, model, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewWinChart$(tips, model, status)
							]))
					])),
				$author$project$Mario$Dashboard$band$(
				'What is it doing?',
				'What the next episodes are being spent on, and what would open the next gate.',
				_List_fromArray(
					[
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewNowPlaying$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewNextGate$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewAllocation$(tips, status)
							]))
					])),
				$author$project$Mario$Dashboard$band$(
				'Is it learning?',
				'Whether the search is still finding structure, and where the aggregate hides a weakness.',
				_List_fromArray(
					[
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-4')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewPopulation$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-4')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewSpeciesChart$(tips, model, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-4')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewNodesChart$(tips, model, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewShipPerformance$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewHeatmap$(tips, model, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewTopology$(tips, model, status)
							]))
					])),
				$author$project$Mario$Dashboard$band$(
				'Is it healthy?',
				'What the work costs, where the time goes, and what the machine is allowed to spend.',
				_List_fromArray(
					[
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewThroughput$(tips, model, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewPhaseSplit$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewBenchmark$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-6')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewMachine$(tips, status)
							])),
						A2(
						$elm$html$Html$section,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('col-12')
							]),
						_List_fromArray(
							[
								$author$project$Mario$Dashboard$viewEvents$(tips, status)
							]))
					]))
			]);
	}
};
var $elm$svg$Svg$polygon = $elm$svg$Svg$trustedNode('polygon');
var $author$project$Mario$Dashboard$crest = A2(
	$elm$svg$Svg$svg,
	_List_fromArray(
		[
			$elm$svg$Svg$Attributes$class('crest'),
			$elm$svg$Svg$Attributes$viewBox('0 0 40 40'),
			A2($elm$html$Html$Attributes$attribute, 'aria-hidden', 'true')
		]),
	_List_fromArray(
		[
			A2(
			$elm$svg$Svg$polygon,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$points('20,2 36,11 36,29 20,38 4,29 4,11'),
					$elm$svg$Svg$Attributes$fill('none'),
					$elm$svg$Svg$Attributes$stroke('#ffb23f'),
					$elm$svg$Svg$Attributes$strokeWidth('1.6')
				]),
			_List_Nil),
			A2(
			$elm$svg$Svg$polygon,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$points('20,9 30,14.5 30,25.5 20,31 10,25.5 10,14.5'),
					$elm$svg$Svg$Attributes$fill('none'),
					$elm$svg$Svg$Attributes$stroke('#4fd6e0'),
					$elm$svg$Svg$Attributes$strokeWidth('1.2')
				]),
			_List_Nil),
			A2(
			$elm$svg$Svg$circle,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$cx('20'),
					$elm$svg$Svg$Attributes$cy('20'),
					$elm$svg$Svg$Attributes$r('3.2'),
					$elm$svg$Svg$Attributes$fill('#f4ead6')
				]),
			_List_Nil),
			A2(
			$elm$svg$Svg$line,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$x1('20'),
					$elm$svg$Svg$Attributes$y1('9'),
					$elm$svg$Svg$Attributes$x2('20'),
					$elm$svg$Svg$Attributes$y2('16.8'),
					$elm$svg$Svg$Attributes$stroke('#4fd6e0'),
					$elm$svg$Svg$Attributes$strokeWidth('1')
				]),
			_List_Nil),
			A2(
			$elm$svg$Svg$line,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$x1('20'),
					$elm$svg$Svg$Attributes$y1('23.2'),
					$elm$svg$Svg$Attributes$x2('20'),
					$elm$svg$Svg$Attributes$y2('31'),
					$elm$svg$Svg$Attributes$stroke('#4fd6e0'),
					$elm$svg$Svg$Attributes$strokeWidth('1')
				]),
			_List_Nil)
		]));
var $elm$html$Html$h1 = _VirtualDom_node('h1');
var $author$project$Mario$Dashboard$Pause = 0;
var $author$project$Mario$Dashboard$Resume = 1;
var $author$project$Mario$Dashboard$Stop = 2;
var $author$project$Mario$Dashboard$Copy$controls = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'controls',
	'Run controls',
	'Pause halts the loop at a safe boundary, so a resume continues the same trajectory rather than restarting a batch differently. Stop shuts the run down after writing a checkpoint. Both are requests to the trainer: the button shows a pending state until the trainer acknowledges, and a failure is reported rather than silently assumed to have worked.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; actions.'),
			_Utils_Tuple2('Window', 'Immediate.'),
			_Utils_Tuple2('Source', 'POST to the local control endpoint on the loopback interface.')
		]));
var $elm$json$Json$Encode$bool = _Json_wrap;
var $elm$html$Html$Attributes$boolProperty$ = function (key, bool) {
	return A2(
		_VirtualDom_property,
		key,
		$elm$json$Json$Encode$bool(bool));
};
var $elm$html$Html$Attributes$boolProperty = F2($elm$html$Html$Attributes$boolProperty$);
var $elm$html$Html$Attributes$disabled = $elm$html$Html$Attributes$boolProperty('disabled');
var $author$project$Mario$Dashboard$viewControls$ = function (tips, model) {
	var stopped = $elm$core$Maybe$withDefault$(
		false,
		$elm$core$Maybe$map$(
			function (s) {
				return _Utils_eq(s.bz, $author$project$Mario$Dashboard$Api$Stopped);
			},
			model.aI));
	var pendingFor = function (action) {
		var _v1 = model.aV;
		switch (_v1.$) {
			case 1:
				var a = _v1.a;
				return _Utils_eq(a, action);
			case 2:
				var a = _v1.a;
				return _Utils_eq(a, action);
			default:
				return false;
		}
	};
	var live = $elm$core$Maybe$withDefault$(
		false,
		$elm$core$Maybe$map$(
			function (s) {
				return $author$project$Mario$Dashboard$Api$phaseIsLive(s.bz);
			},
			model.aI));
	var busy = function () {
		var _v0 = model.aV;
		switch (_v0.$) {
			case 1:
				return true;
			case 2:
				return true;
			default:
				return false;
		}
	}();
	var controlButton = F3(
		function (action, extraClass, enabled) {
			return A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class(
						'btn ' + (pendingFor(action) ? 'btn-pending' : extraClass)),
						$elm$html$Html$Attributes$disabled(busy || (!enabled)),
						A2($elm$html$Html$Attributes$attribute, 'aria-live', 'polite'),
						$elm$html$Html$Events$onClick(
						$author$project$Mario$Dashboard$RequestControl(action))
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						pendingFor(action) ? ($author$project$Mario$Dashboard$actionLabel(action) + '\u2026') : $author$project$Mario$Dashboard$actionLabel(action))
					]));
		});
	return _List_fromArray(
		[
			$author$project$Mario$Dashboard$Tip$view$(
			tips,
			1,
			$author$project$Mario$Dashboard$Copy$controls,
			_List_fromArray(
				[
					A3(controlButton, 0, '', live),
					A3(controlButton, 1, 'btn-primary', (!live) && (!stopped)),
					A3(controlButton, 2, 'btn-danger', !stopped)
				])),
			A2(
			$elm$html$Html$button,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('btn'),
					$elm$html$Html$Events$onClick($author$project$Mario$Dashboard$RefreshNow)
				]),
			_List_fromArray(
				[
					$elm$html$Html$text('Refresh')
				]))
		]);
};
var $author$project$Mario$Dashboard$viewControls = F2($author$project$Mario$Dashboard$viewControls$);
var $author$project$Mario$Dashboard$Copy$freshness = A4(
	$author$project$Mario$Dashboard$Copy$t,
	'freshness',
	'Snapshot age',
	'How long ago the trainer last wrote this status. The dashboard polls every two seconds while the tab is visible. If this grows while the phase says training or auditing, the trainer is stalled, wedged, or gone, and every number below is stale rather than current.',
	_List_fromArray(
		[
			_Utils_Tuple2('Denominator', 'None; an age in seconds.'),
			_Utils_Tuple2('Window', 'Now minus the reported updated_at.'),
			_Utils_Tuple2('Source', 'Trainer clock, compared against this browser\'s clock.')
		]));
var $author$project$Mario$Dashboard$viewFreshnessPill$ = function (tips, model) {
	var tone = (!_Utils_eq(model.bj, $elm$core$Maybe$Nothing)) ? 'pill-bad' : ($author$project$Mario$Dashboard$isStale(model) ? 'pill-warn' : 'pill-idle');
	var label = function () {
		var _v0 = model.cL;
		if (_v0.$ === 1) {
			return 'no snapshot';
		} else {
			return $author$project$Mario$Dashboard$Format$decimal$(0, model.bi) + 's old';
		}
	}();
	return $author$project$Mario$Dashboard$Tip$view$(
		tips,
		1,
		$author$project$Mario$Dashboard$Copy$freshness,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('pill ' + tone)
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(label)
					]))
			]));
};
var $author$project$Mario$Dashboard$viewFreshnessPill = F2($author$project$Mario$Dashboard$viewFreshnessPill$);
var $author$project$Mario$Dashboard$viewPhasePill$ = function (tips, model) {
	var _v0 = function () {
		var _v1 = model.aI;
		if (_v1.$ === 1) {
			return _Utils_Tuple2('pill-idle', 'Connecting');
		} else {
			var status = _v1.a;
			return _Utils_Tuple2(
				function () {
					var _v2 = status.bz;
					switch (_v2.$) {
						case 3:
							return 'pill-warn';
						case 4:
							return 'pill-warn';
						case 1:
							return 'pill-ok';
						case 2:
							return 'pill-ok';
						case 0:
							return 'pill-idle';
						default:
							return 'pill-idle';
					}
				}(),
				$author$project$Mario$Dashboard$Api$phaseLabel(status.bz));
		}
	}();
	var tone = _v0.a;
	var label = _v0.b;
	return $author$project$Mario$Dashboard$Tip$view$(
		tips,
		1,
		$author$project$Mario$Dashboard$Copy$phase,
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('pill ' + tone)
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('dot')
							]),
						_List_Nil),
						$elm$html$Html$text(label)
					]))
			]));
};
var $author$project$Mario$Dashboard$viewPhasePill = F2($author$project$Mario$Dashboard$viewPhasePill$);
var $author$project$Mario$Dashboard$viewMasthead = function (model) {
	var tips = $author$project$Mario$Dashboard$tipHandlers(model);
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('masthead')
			]),
		_List_fromArray(
			[
				$author$project$Mario$Dashboard$crest,
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('masthead-titles')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h1,
						_List_Nil,
						_List_fromArray(
							[
								$elm$html$Html$text('MarI/O Mission Control')
							])),
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('eyebrow')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								function () {
									var _v0 = model.aI;
									if (!_v0.$) {
										var status = _v0.a;
										return 'run ' + status.i1;
									} else {
										return 'local trainer, loopback only';
									}
								}())
							]))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('masthead-spacer')
					]),
				_List_Nil),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('masthead-actions')
					]),
				A2(
					$elm$core$List$cons,
					$author$project$Mario$Dashboard$viewPhasePill$(tips, model),
					A2(
						$elm$core$List$cons,
						$author$project$Mario$Dashboard$viewFreshnessPill$(tips, model),
						$author$project$Mario$Dashboard$viewControls$(tips, model))))
			]));
};
var $author$project$Mario$Dashboard$view = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('page')
			]),
		A2(
			$elm$core$List$cons,
			$author$project$Mario$Dashboard$viewMasthead(model),
			_Utils_ap(
				$author$project$Mario$Dashboard$viewBanners(model),
				$author$project$Mario$Dashboard$viewBody(model))));
};
var $author$project$Mario$Dashboard$main = $elm$browser$Browser$element(
	{kk: $author$project$Mario$Dashboard$init, lk: $author$project$Mario$Dashboard$subscriptions, lw: $author$project$Mario$Dashboard$update, lA: $author$project$Mario$Dashboard$view});
_Platform_export({'Mario':{'Dashboard':{'init':$author$project$Mario$Dashboard$main(
	$elm$json$Json$Decode$succeed(0))(0)}}});function _Debug_toAnsiString(ansi, value)
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

  if (x.$ < 0)
{
  if (x.$ < -10)
  {
    x = $lamdera$containers$SeqDict$toList(x);
    y = $lamdera$containers$SeqDict$toList(y);
  }
  else
  {
    x = $elm$core$Dict$toList(x);
    y = $elm$core$Dict$toList(y);
  }
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

