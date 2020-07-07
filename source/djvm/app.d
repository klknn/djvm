module djvm.app;

import core.stdc.stdlib : exit;
import core.stdc.stdio : fopen, fread, printf, FILE;

import djvm.logging : error, info;

// @nogc nothrow:

struct Const
{  
  /// Table 4.4-A. Constant pool tags (by section)
  /// https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html
  enum Tag
  {
    // literals
    Utf8 = 0x01,
    Integer = 0x03,
    Float = 0x04,
    Long = 0x05,
    Double = 0x06,

    Class = 0x07,
    String = 0x08,
    Fieldref = 0x09,
    Methodref = 0x0a,
    InterfaceMethodref = 0x11,
    NameAndType = 0x0c,

    // from Java 7 (51.0)
    MethodHandle = 0x0f,
    MethodType = 0x10,
    InvokeDynamic = 0x12,

    // from Java 9 (53.0)
    Module = 0x13,
    Package = 0x14,

    // from Java 11 (55.0)
    Dynamic = 0x11,
  }

  Tag tag;

  // TODO: use union
  ushort nameIndex, classIndex, nameAndTypeIndex, stringIndex, descriptorIndex;
  string str = "";
}

string utf8(const ref Const c)
{
  if (c.tag != Const.Tag.Utf8)
  {
    info("wrong tag %#x (expected Utf8)", c.tag);
    return "";
  }
  return c.str;
}

/// Reads one Const value from the given binary file.
ref read(return ref Const c, scope FILE* fd)
{
  import core.stdc.stdlib : malloc;

  c = Const.init;
  c.tag = cast(Const.Tag) fd.read!ubyte;
  with (Const.Tag)
  {
    // TODO: final switch
    switch (c.tag)
    {
      case Utf8:
        auto len = fd.read!ushort;
        // TODO: free if possible
        auto dst = cast(char*) malloc(len + 1);
        auto n = fread(dst, len, 1, fd);
        assert(n == 1);
        dst[len] = 0;  // null terminated
        c.str = cast(string) dst[0 .. len];
        info("read str: %s", dst);
        break;
      case Class:
        c.nameIndex = fd.read!ushort;
        break;
      case String:
        c.stringIndex = fd.read!ushort;
        break;
      case Fieldref:
      case Methodref:
        c.classIndex = fd.read!ushort;
        c.nameAndTypeIndex = fd.read!ushort;
        break;
      case NameAndType:
        c.nameIndex = fd.read!ushort;
        c.descriptorIndex = fd.read!ushort;
        break;
      default:
        error("unsupported tag: %#x", c.tag);
    }
  }
  return c;
}

ref read(return ref Const[] cs, scope FILE* fd)
{
  import core.stdc.stdlib : realloc;
  
  auto count = fd.read!ushort - 1;
  info("const pool count: %d", count);

  auto p = cast(Const*) realloc(cs.ptr, Const.sizeof * count);
  if (p is null) error("realloc failed.");

  cs = p[0 .. count];
  foreach (i; 0 .. count)
  {
    cs[i].read(fd);
  }
  return cs;
}

struct Attribute
{
  string name;
  byte[] data;
}

struct Field
{
  ushort flags;
  string name;
  string descriptor;
  Attribute[] attributes;
}

struct Class
{
  Const[] constPool;
  Const thisClass;
  Const superClass;
  ushort flags;
  string[] interfaces;
  Field[] fields;
  Field[] methods;
  Attribute[] attributes;

  ref read(return ref Attribute[] as, FILE* fd)
  {
    import core.stdc.stdlib : realloc;

    auto len = fd.read!ushort;
    auto ptr = cast(Attribute*) realloc(as.ptr, Attribute.sizeof * len);
    if (ptr is null) error("realloc failed.");
    as = ptr[0 .. len];
    foreach (ref a; as)
    {
      a = Attribute.init;
      a.name = this.constPool[fd.read!ushort - 1].utf8;
      info("attribute name: %s", a.name.ptr);
      // FIXME: really uint?
      auto dn = fd.read!uint;
      auto dp = cast(byte*) realloc(a.data.ptr, dn);
      info("attribute bytes: %d", dn);
      if (dp is null) error("realloc failed");
      a.data = dp[0 .. dn];
      auto n = fread(dp, dn, 1, fd);
      if (n != 1) error("fread failed at Attribute: %s.", a.name.ptr);
    }
    return as;
  }
  
  ref read(return ref Field[] fs, FILE* fd)
  {
    import core.stdc.stdlib : realloc;
    
    auto len = fd.read!ushort;
    auto ptr = cast(Field*) realloc(fs.ptr, Field.sizeof * len);
    if (ptr is null) error("realloc failed.");
    fs = ptr[0 .. len];
    foreach (ref f; fs)
    {
      f = Field.init;
      f.flags = fd.read!ushort;
      f.name = this.constPool[fd.read!ushort - 1].utf8;
      info("field/method name: %s", f.name.ptr);
      f.descriptor = this.constPool[fd.read!ushort - 1].utf8;
      info("field/method descriptor: %s", f.descriptor.ptr);
      read(f.attributes, fd);
    }
    return fs;
  }

  ref read(scope FILE* fd)
  {
    import core.stdc.stdlib : malloc;
  
    // Check the first 4 numbers.
    ubyte[4] magic;
    fread(magic.ptr, 4, 1, fd);
    static immutable expected = [0xca, 0xfe, 0xba, 0xbe];
    assert(magic == expected);

    // Check class file version.
    auto minor = fd.read!ushort;
    auto major = fd.read!ushort;
    info("Class version: %d.%d", major, minor); 

    // Read fields.
    this.constPool.read(fd);  
    this.flags = fd.read!ushort;
    // FIXME: Is "- 1" needed?
    this.thisClass = this.constPool[fd.read!ushort - 1];
    this.superClass = this.constPool[fd.read!ushort - 1];

    // Read interfaces
    auto ilen = fd.read!ushort;
    info("interface count: %d", ilen);
    auto iptr = cast(string*) malloc(string.sizeof * ilen);
    foreach (i; 0 .. ilen)
    {
      iptr[i] = this.constPool[fd.read!ushort - 1].utf8;
      info("interface: %s", iptr[i].ptr);
    }
    this.interfaces = iptr[0 .. ilen];

    // Read fields
    read(this.fields, fd);
    info("field count: %d", this.fields.length);
    read(this.methods, fd);
    info("method count: %d", this.methods.length);
    read(this.attributes, fd);
    info("attribute count: %d", this.attributes.length);
    return this;
  }
}

/// Reads integer values from the given binary file.
T read(T)(FILE* fd)
{
  import std.bitmanip : bigEndianToNative;

  ubyte[T.sizeof] buf;
  auto n = fread(buf.ptr, T.sizeof, 1, fd);
  if (n != 1)
  {
    error("unexpected EOF");
  }
  // Multibyte data items are always stored in big-endian order.
  return bigEndianToNative!T(buf);
}

int main(string[] args)
{
  import std.stdio;
  // Check args.
  if (args.length != 2)
  {
    error("usage: %s file.class", &args[0][0]);
  }

  // Open a class file.
  auto fname = &args[1][0];
  auto fd = fopen(fname, "rb");
  if (fd is null)
  {
    error("unable to open %s", fname);
  }

  Class c;
  c.read(fd);
  foreach (i, v; c.constPool)
  {
    writeln(i, v);
  }
  return 0;
}
