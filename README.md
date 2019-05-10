# lua_params

lua module capable of opening and saving Smash Ultimate param files via a table structure. Assumes lua version 5.3

## structure

OPEN(filename) returns a ROOT node containing all other params

nodes can be one of multiple types:

```lua
TYPES = {
    "bool",
    "sbyte",
    "byte",
    "short",
    "ushort",
    "int",
    "uint",
    "float",
    "hash40",
    "string",
    "list",
    "struct"
}
```

each node is considered a table, and there are 3 categories depending on the type.

structs:

    TYPE    (always equal to "struct")
    HASHES  (an ordered list of the hashes in the struct used to access nodes)
    NODES   (a dictionary of nodes accessed by hash)
    
lists:

    TYPE    (always equal to "list")
    NODES   (an ordered list of nodes; these are assumed to be the same type)

values:

    TYPE    (anything else except "struct" and "list")
    VALUE   (a value depending on the type)

the ROOT of a param file is always a struct
