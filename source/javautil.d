///
module kaleidic.api.carbon.jni.javautil;
import jni;
import std.stdio;
import std.string;
static import std.file;
import std.exception:enforce;
import std.datetime;
import std.array:Appender,array;
import std.format;
import core.thread;
import core.time;
import std.algorithm;
//import kaleidic.api.carbon.subscribe;
import std.conv:to;
import std.typecons:Tuple,tuple;
version(LDC)
{
	import std.meta:Alias;
	import kaleidic.api.carbon.ldcutil;
}
else
{
	import std.meta:Repeat,Alias;
}
import core.stdc.stdio:printf;

///
enum JNI_VERSION = JNI_VERSION_1_6;
///
__gshared KaleidicJVM* kaleidicJVM;

///
struct JavaException
{
	bool isException = false;
	alias isException this;
	string message;
}

///
JavaException checkJavaException(JavaEnvironment* envWrap)
{
	auto env=envWrap.p;
	enforce(env !is null, "checkJavaException called on null JNI Env*");
	enforce(*env !is null, "checkJavaException called on null JNI Env");
	JavaException ret;
	jthrowable exc = (*env).ExceptionOccurred(env);
	ret.isException = ((((*env).ExceptionCheck(env))==JNI_TRUE) && (exc !is null));
	//ret.isException = (exc !is null); // ((*env).ExceptionCheck(env)==JNI_TRUE);
	if (ret.isException)
	{
		(*env).ExceptionDescribe(env);
		//if (env !is null)
		//	return ret;
		enforce(exc !is null, "cannot get exception from java");
		jclass exceptionClass= findClassAtila(env,"java/lang/Throwable");
		//FindClass(env,"java/lang/Throwable".toCString);
		//jclass exceptionClass = (*env).GetObjectClass(env,exc);
		enforce(exceptionClass !is null, "cannot get exception class from java");
		jclass classClass = findClassAtila(env,"java/lang/Throwable");
		enforce(classClass !is null, "cannot get class Throwable from java");

		jmethodID getName= (*env).GetMethodID(env,exceptionClass,"getName".toCString,"()Ljava/lang/String;".toCString);
		enforce (getName !is null, "cannot GetMethodID for getName whilst rethrowing java exception");

		jmethodID printStackTrace = (*env).GetMethodID(env,exceptionClass,"printStackTrace".toCString,"()V");
		enforce(printStackTrace !is null, "cannot get printStackTrace method");
		(*env).CallObjectMethod(env,exc,printStackTrace);
		jstring name = cast(jstring)((*env).CallObjectMethod(env,exceptionClass,getName,null));
		char* message;
		if (name is null)
		{
			stderr.writefln("cannot get name of exception class from java");
			ret.message = "Unknown Exception Class / ";
		}
		else
		{
			auto p = (*env).GetStringUTFChars(env,name,null);
			ret.message = p.fromStringz.dup;
			(*env).ReleaseStringUTFChars(env,&name,p);
		}

		if (env !is null)
		{
			(*env).ExceptionClear(env);
			return ret;
		}
		//jmethodID getMessage= (*env).GetMethodID(env,exceptionClass,"getMessage".toCString,"()Ljava/lang/String;".toCString);
		//enforce (getMessage !is null, "cannot GetMethodID for getMessage whilst rethrowing java exception");
		//jstring message= cast(jstring)((*env).CallObjectMethod(env,exceptionClass,getMessage));
		//jstring message= cast(jstring)((*env).CallObjectMethod(env,exceptionClass,
		auto p = (*env).GetStringUTFChars(env,message,null);
		ret.message ~= " " ~ p.fromStringz.dup;
		(*env).ReleaseStringUTFChars(env,&ret.message,p);
		(*env).ExceptionClear(env);
	}
	return ret;
}

/// JNI FindClass() cannot find a class if it is called by a new thread
/// http://discuss.cocos2d-x.org/t/jni-findclass-cannot-find-a-class-if-its-called-by-a-new-pthread/1873
/// geniuses!
struct ClassHandle
{
	jclass handle;
	alias handle this;
	this(JNIEnv* env, string className)
	{
		handle = (*env).FindClass(env,className.toCString);
		if ((*env).ExceptionOccurred(env))
			(*env).ExceptionDescribe(env);

		enforce(env !is null, "unable to find " ~ className ~ " class");
		handle = (*env).NewGlobalRef(env,handle);
		enforce(handle !is null, "unable to get global ref to " ~ className ~ " class");
		writefln("* found " ~ className ~ " class successfully");
	}
}

///
struct KaleidicJVM
{
	@disable this();
	@disable this(this);
	JavaVMOption[] options;
	JavaVM *jvm;
	JNIEnv* env;
	alias jvm this;
	JavaVMInitArgs vm_args;
	ClassHandle[string] classHandles;

	static KaleidicJVM* factory()
	{
       		if (kaleidicJVM !is null)
		{
			stderr.writefln("trying to create a JVM when it already exists!");
			return kaleidicJVM;
		}
		static KaleidicJVM factoryJVM = void;
		return &factoryJVM;
	}

	void create(string[] jvmOptions)
	{
		this.options= new JavaVMOption[jvmOptions.length];
		foreach(i,option;jvmOptions)
			options[i].optionString = option.toCString;
		vm_args.version_ = JNI_VERSION;
		vm_args.nOptions = 1;
		vm_args.options = options.ptr;
		vm_args.ignoreUnrecognized = false;
		auto status = JNI_CreateJavaVM(&jvm, &env, &vm_args);
		writefln("JVM created: status = %s",status); stdout.flush;
		enforce(status!=JNI_ERR, "Unable to start JVM");
		classHandles["java/lang/String"] = ClassHandle(env,"java/lang/String");
		classHandles["symmetry/carbon/example/KaleidicCarbonClient"] = ClassHandle(env,"symmetry/carbon/example/KaleidicCarbonClient");
		JNI_OnLoad2(jvm,null);
	}
}

///
__gshared jobject gClassLoader;
///
__gshared jmethodID gFindClassMethod;

///
extern(C) jint JNI_OnLoad2(JavaVM *pjvm, void* reserved)
{
	printf("*JNI_OnLoad started");
	auto env = getEnv();
	printf("*JNI_OnLoad getEnv");
	auto classLoaderClass = (*env).FindClass(env,"java/lang/ClassLoader");
	printf("*JNI_OnLoad classLoader");
	auto randomClass = (*env).FindClass(env,"symmetry/carbon/example/KaleidicCarbonClient");
	printf("*JNI_OnLoad random");
	jclass classClass = (*env).GetObjectClass(env,randomClass);
	printf("*JNI_OnLoad classClass");
	auto getClassLoaderMethod = (*env).GetMethodID(env,classClass,"getClassLoader","()Ljava/lang/ClassLoader;");
	printf("*JNI_OnLoad getClassLoaderMethod");
	gClassLoader = (*env).CallObjectMethod(env,randomClass,getClassLoaderMethod);
	gClassLoader = (*env).NewGlobalRef(env,gClassLoader);
	printf("*JNI_OnLoad gClassLoader");
	gFindClassMethod = (*env).GetMethodID(env,classLoaderClass,"findClass","(Ljava/lang/String;)Ljava/lang/Class;");
	printf("*JNI_OnLoad returning");
	return JNI_VERSION;
}

///
jclass findClassAtila(JNIEnv* pEnv,string name)
{
	version(Atila)
	{
		writefln("* looking for class %s",name);
		auto javaName = (*pEnv).NewStringUTF(pEnv,name.toCString);
		writefln("javaname: %s",javaName);
		writefln("gClassLoader: %s",gClassLoader);
		writefln("gFindClassMethod: %s",gFindClassMethod);
		auto ret = cast(jclass) ((*pEnv).CallObjectMethod(pEnv,gClassLoader,gFindClassMethod,javaName));
	}
	else
	{
		auto ret = (*pEnv).FindClass(pEnv,name.toCString);
		ret= (*pEnv).NewGlobalRef(pEnv,ret);
	}
	writefln("findClass: %s",ret);
	return ret;
}

///
JNIEnv* getEnv()
{
	JNIEnv* env;
	auto status = (*kaleidicJVM.jvm).GetEnv(kaleidicJVM.jvm,cast(void**)&env,JNI_VERSION);
	if (status<0)
	{
		status = (*kaleidicJVM.jvm).AttachCurrentThread(kaleidicJVM.jvm,cast(void**)&env,null);
		assert(status>=0);
		if (status<0)
			return null;
	}
	writefln("* survived getEnv");
	return env;
}

///
shared static ~this()
{
	version(None) // JVM will hang if you try to be nice and clean up
	{
		if (kaleidicJVM.jvm !is null)
			(*kaleidicJVM.jvm).DestroyJavaVM(kaleidicJVM.jvm);
	}
}

///
struct JavaEnvironment
{
	@disable this();
	@disable this(this);
	JNIEnv* p;
	alias p this;
	jmethodID stringConstructorMethodID;

	jclass classString() // hack to avoid rewriting code
	{
		writefln("classString called");
		// return findClassAtila(p,"java/lang/String");
		auto p = "java/lang/String" in kaleidicJVM.classHandles;
		return (p is null) ? p : *p;
	}
	void classString(jclass arg)
	{
		if (arg is null)
			kaleidicJVM.classHandles.remove("java/lang/String");
		else
			kaleidicJVM.classHandles["java/lang/String"] = arg;
	}

	this(string classPath)
	{
		auto status = (*kaleidicJVM.jvm).GetEnv(kaleidicJVM.jvm,cast(void**)&this.p,JNI_VERSION);
		if ((*this.p).ExceptionOccurred(this.p))
			(*this.p).ExceptionDescribe(this.p);
		switch(status)
		{
			case JNI_OK:
				writefln("* thread already attached");
				break;

			case JNI_EVERSION:
				assert(0,"JNI version mismatch");

			case JNI_EDETACHED:
				auto attachStatus = (*(kaleidicJVM.jvm)).AttachCurrentThread(kaleidicJVM.jvm,cast(void**)&this.p,null); // &this.vm_args);
				if (attachStatus == JNI_OK)
					writefln("* thread attached");
				else
					writefln("* attempt to attach thread failed with status %s",attachStatus);
				break;

			default:
				writefln("* unknown JNI GetEnv return: %s",status);
				break;
		}
		enforce(this.p !is null, "unable to attach carbon to JVM - null env returned");
		enforce(*this.p !is null, "unable to attach carbon to JVM - null env* returned");
		writefln("* obtained environment successfully");
		//this.p=kaleidicJVM.env;
		enforce(classString() !is null, "unable to find String class");
		writefln("* found string class successfully");
		stringConstructorMethodID= (*this.p).GetMethodID(this.p,classString, "<init>","(Ljava/lang/String;)V");
		enforce(stringConstructorMethodID!is null, "null stringConstructorMethodID");
	}

	~this()
	{
		// needs to be called from same thread
	}
	void dispose()
	{
		if (classString !is null)
		{
			(*this.p).DeleteGlobalRef(this.p,classString);
			this.classString = null;
		}
		if (this.p !is null)
		{
			(**kaleidicJVM.jvm).DetachCurrentThread((*kaleidicJVM).jvm);
			this.p = null;
		}
	}
}

///
jclass findClass(bool noThrow=false)(JavaEnvironment* env, string className)
{
	enforce(env.p !is null,"FindClass called on null env for class: " ~ className);
	auto ret = (*(*env).p).FindClass(env.p,className.toCString);
	static if(!noThrow)
	{
		enforce(ret !is null, "findClass failed for class: " ~ className);
	}
	return ret;
}

///
jclass newGlobalRef(bool noThrow = false)(JavaEnvironment* env, jclass classRef)
{
	enforce(env.p !is null,"newGlobalRef called on null env");
	auto ret = (*(*env.p)).NewGlobalRef(*env,classRef);
	static if(!noThrow)
	{
		enforce(ret !is null, "newGlobalRef return null");
	}
	return ret;
}

///
void deleteGlobalRefRaw(bool noThrow = false)(JNIEnv * env, jclass classRef)
{
	enforce(env !is null,"deleteGlobalRef called on null env");
	(*env).DeleteGlobalRef(env,classRef);
	static if(!noThrow)
	{
		auto e =env.checkJavaException();
		enforce(!e, "Java Exception when destroying Global Ref");
	}
}

///
void deleteGlobalRef(bool noThrow = false)(JavaEnvironment* env, jclass classRef)
{
	enforce(env.p !is null,"deleteGlobalRef called on null env");
	(*(*env.p)).DeleteGlobalRef(*env,classRef);
	static if(!noThrow)
	{
		auto e =env.checkJavaException();
		enforce(!e, "Java Exception when destroying Global Ref");
	}
}

///
void deleteLocalRef(bool noThrow = false)(JavaEnvironment* env, jclass classRef)
{
	enforce(env.p !is null,"deleteLocalRef called on null env");
	(*(*env.p)).DeleteLocalRef(*env,classRef);
	static if(!noThrow)
	{
		auto e =env.checkJavaException();
		enforce(!e, "Java Exception when destroying Local Ref");
	}
}



///
auto getFieldID(bool noThrow = false,T)(JavaEnvironment* env, T classRef, string fieldName, string fieldType)
if (is(T==jclass) || is(T==void*))
{
	enforce(env.p !is null,"getFieldID called on null env");
	auto ret = (*(*env.p)).GetFieldID(env.p,classRef,fieldName.toCString,fieldType.toCString);
	static if(!noThrow)
	{
		enforce(ret !is null, "getFieldID return null");
	}
	return ret;
}

///
jmethodID getMethodID(bool noThrow = false,T)(JavaEnvironment* env, T classRef, string methodName, string signature)
if (is(T==jclass) || is(T==void*))
{
	enforce(env.p !is null,"getMethodID called on null env for method: " ~ methodName ~ " and signature: "~signature);
	enforce(classRef !is null,"getMethodID called on null classref for method: " ~ methodName ~ " and signature: "~signature);
	auto ret = (*(*env).p).GetMethodID(env.p,classRef, methodName.toCString, signature.toCString);
	static if(!noThrow)
	{
		enforce(ret !is null, "getMethodID failed for method: " ~ methodName);
	}
	return ret;
}

///
jmethodID getConstructor(bool noThrow = false,T)(JavaEnvironment* env, T classRef, string signature)
if (is(T==void*)||(T==jclass))
{
	return env.getMethodID!noThrow(cast(void*)classRef,"<init>",signature);
}



///
string fromJavaString(JavaEnvironment* env,jstring javaString)
{
	auto n = (*(*env).p).GetStringUTFLength(env.p,javaString);
	ubyte[] buf;
	buf.length=n+1;
	auto p = (*(*env).p).GetStringUTFChars(env.p,javaString,buf.ptr);
	auto s = p[0..n].idup;
	(*(*env.p)).ReleaseStringUTFChars(env.p,javaString,p);
	auto e = checkJavaException(env);
	enforce (!e, "fromJavaString generated Java Exception: "~e.message);
	return s;
}


///
struct JavaString(bool autoDestroy = false)
{
	//@disable this(this);
	jstring str;
	alias str this;
	JavaEnvironment* env;
	string debugString;

	this(JavaEnvironment* env, string inputString)
	{
		debugString = inputString;
		this.env = env;
		enforce(this.env.p !is null,"JavaString constructor called with null env");
		if (inputString is null)
			inputString="";
		this.str = (*(*this.env).p).NewStringUTF(this.env.p,inputString.toCString);
		auto e = checkJavaException(env);
		enforce (!e, "JavaString constructor for " ~ inputString ~ " generated Java Exception: "~e.message);
	}

	~this()
	{
		static if(autoDestroy)
			dispose();
	}
	void dispose()
	{
		if ((env !is null) && (env.p !is null) && (this.str !is null))
		{
			(*(*env).p).DeleteLocalRef(env.p,this.str);
			this.str = null;

			auto e = checkJavaException(env);
			enforce (!e, "JavaString destructor generated Java Exception: "~e.message);
			this.env=null;
		}
		writefln("destroyString %s",debugString);
	}
}

///
auto toJavaString(bool autoDestroy = false)(JavaEnvironment* env, string inputString)
{
	return JavaString!autoDestroy(env,inputString);
}
	/+
jstring toJavaString(JNIEnv* env, string inputString)
{
	return (**env).NewStringUTF(env,inputString.toCString);
}
+/

///
const(char)* toCString(string s)
{
	return cast(char*)s.toStringz;
}

///
auto skipGarbageStart(string s)
{
	import std.algorithm:min;
	auto i= s[0..min(20,s.length)].indexOf("{");
	if (i==-1)
		i=s[0..20].indexOf("[");
	return (i==-1) ? s: s[i..$];
}


///
bool getBoolField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,"Z".toCString);
	enforce (fidNumber !is null,"Unable to get bool field "~fieldName);
	return cast(bool) (*env).GetBooleanField(env,thisObj,fidNumber);
}

///
int getIntField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,"I".toCString);
	enforce (fidNumber !is null,"Unable to get int field "~fieldName);
	return (*env).GetIntField(env,thisObj,fidNumber);
}

///
long getLongField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,"J".toCString);
	enforce (fidNumber !is null,"Unable to get long field "~fieldName);
	return (*env).GetLongField(env,thisObj,fidNumber);
}

///
short getShortField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,"S".toCString);
	enforce (fidNumber !is null,"Unable to get short field "~fieldName);
	return (*env).GetShortField(env,thisObj,fidNumber);
}

///
double getDoubleField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,"D".toCString);
	enforce (fidNumber !is null,"Unable to get double field "~fieldName);
	return (*env).GetDoubleField(env,thisObj,fidNumber);
}

///
string getStringField(JavaEnvironment* env, jobject thisObj, jclass thisClass, string fieldName)
{
	auto fidNumber=env.getFieldID(thisClass,fieldName,"Ljava/lang/String");
	auto s = (*(*env).p).GetObjectField(env.p,thisObj,fidNumber);
	enforce (s !is null,"Unable to get string field "~fieldName);
	return fromJavaString(env,s);
}

///
auto getClassField(JNIEnv* env, jobject thisObj, jclass thisClass, string fieldName, string className)
{
	auto fidNumber=(*env).GetFieldID(env,thisClass,fieldName.toCString,("L"~className.dotsToSlashes).toCString);
	auto c = (*env).GetObjectField(env,thisObj,fidNumber);
	enforce (c !is null,"Unable to get class field "~ className ~ ": " ~fieldName);
	return c;
}

///
string dotsToSlashes(string s)
{
	return s.replace("/",".");
}

///
struct JavaObjectArray
{
	JavaEnvironment* env;
	jobjectArray arr;
	alias arr this;

	this(JavaEnvironment* env, size_t length, jclass elementClass, jobject initialElement)
	{
		enforce(env.p !is null, "JavaObjectArray constructor called with null env.p");
		this.env=env;
		auto p = (*(*this.env).p).NewObjectArray(this.env.p,length.to!jsize, elementClass, initialElement);
		auto e = env.checkJavaException;
		enforce (!e, "JavaObjectArray constructor generated Java Exception: "~e.message);
		enforce(p !is null, "unable to create Java Object Array");
		this.arr = env.newGlobalRef(p);
		e = checkJavaException(env);
		enforce (!e, "JavaObjectArray NewGlobalRef generated Java Exception: "~e.message);
		enforce(this.arr !is null, "unable to get global reference for JavaObjectArray");
	}


	this(JavaEnvironment* env, jobjectArray arr)
	{
		enforce(env.p !is null, "JavaObjectArray constructor called with null env");
		enforce(arr !is null, "JavaObjectArray constructor called on null array reference");
		this.env=env;
		this.arr = env.newGlobalRef(arr);
		auto e = env.checkJavaException;
		enforce (!e, "JavaObjectArray constructor generated Java Exception: "~e.message);
		enforce(arr !is null, "Unable to get global reference for JavaObjectArray");
	}
	void dispose()
	{
		if ((this.env.p !is null) && (this.arr !is null))
		{
			env.deleteGlobalRef(this.arr);
			auto e = env.checkJavaException;
			enforce (!e, "JavaObjectArray destructor generated Java Exception: "~e.message);
			this.arr=null;
			this.env=null;
		}
	}
	auto opIndexAssign(jobject val, size_t i)
	{
		enforce(val !is null, "attempting to assign null element to JavaObjectArray for element " ~ i.to!string);
		(*(*env).p).SetObjectArrayElement(env.p,this.arr,i.to!jsize,val);
		auto e = env.checkJavaException;
		enforce (!e, "JavaObjectArray opIndexAssign generated Java Exception: "~e.message);
		return val;
	}
	auto opIndex(size_t i)
	{
		return (*(*env).p).GetObjectArrayElement(env.p,this.arr,i.to!jsize);
	}
	auto length()
	{
		return (*(*env).p).GetArrayLength(env.p,this.arr).to!size_t;
	}

}

/+
struct JavaObject
{
	jobject obj;
	alias obj this;

	this(JNIEnv* env, jobject obj)
	{
		enforce(obj !is null, "JavaObject constructor called on null ref");
		this.obj = (*env).NewGlobalRef(env,obj);
		enforce (this.obj !is null, "Unable to get global reference for JabaObject");
	}
	~this()
	{
		if (this.obj !is null)
		{
			(*env).DeleteGlobalRef(env,this.obj);
			this.obj=null;
		}
	}
}
+/

///
JavaObjectArray toJava(JavaEnvironment* env, string[] arr)
{
	enforce(env.stringConstructorMethodID!is null, "null stringConstructorMethodID");
	enforce(env.classString !is null, "null string class reference");
	auto javaArr = JavaObjectArray(env,arr.length,env.classString,null);
	auto e = env.checkJavaException;
	enforce (!e, "JavaObjectArray toJava generated Java Exception: "~e.message);

	foreach(i,s;arr)
	{
		auto p =(*(*env).p).NewObject(env.p,env.classString,env.stringConstructorMethodID,env.toJavaString!false(s).str);
		enforce (p ! is null, "failed to create string for entry "~i.to!string~ " " ~ s);
		javaArr[i] = p;
	}
	e = env.checkJavaException;
	enforce (!e, "JavaObjectArray toJava generated Java Exception: "~e.message);
	return javaArr;
}


	/*
	   auto rawP = ((*env).NewObjectArray(env,arr.length.to!int,classString,null));
	enforce (rawP !is null, "unable to create string[] Java array");
	auto p = JavaObjectArray(env,rawP);

	enforce(constructString !is null, "failed to get string constructor for " ~ arr.to!string);
	foreach(i,s;arr)
	{
		jobject rawEntry = (*env).NewObject(env,classString,constructString,env.toJavaString(s));
		enforce(rawEntry !is null, "failed to create string for entry "~i.to!string~" "~s);
		auto entry = JavaObject(env,rawEntry);
		(*env).SetObjectArrayElement(env,p,i.to!int,entry);
	}
	return p;
} */

///
string[] fromJava(T:string[])(JNIEnv* env, jobjectArray arr)
{
	string[] ret;
	ret.length = (*env).GetArrayLength(env,arr);
	// auto classString =(*env).FindClass(env,"java/lang/String");
	auto e = env.checkJavaException;
	enforce (!e, "fromJava generated Java Exception: "~e.message);
	enforce(classString !is null, "string class ref is null");
	auto midStrValue = (*env).GetMethodID(env,classString,"stringValue","()Ljava/lang/String");
	foreach(i;0..ret.length)
	{
		jobject entry = (*env).GetObjectArrayElement(env,arr,i);
		e = env.checkJavaException;
		enforce (!e, "fromJava generated Java Exception: "~e.message);
		enforce (entry !is null, "unable to get element number "~i.to!string~ " for array conversion");
		ret[i] = (*env).CallStringMethod(env,entry,midStrValue);
	}
	return ret;
}

///
auto toJavaString(bool autoDestroy = false)(JavaEnvironment* env, DateTime date)
{
	Appender!string s;
	s.put(format("%04d-%02d-%02d %02d:%02d:%02d",
				date.year,
				date.month,
				date.day,
				date.hour,
				date.minute,
				date.second));
	return env.toJavaString!autoDestroy(s.data);
}



///
template ToJavaString(args...)
{
	///
	alias JavaStringTup = Repeat!(args.length,JavaString!false);

	///
	auto create(JavaEnvironment* env)
	{
		JavaString!false[args.length] ret;
		foreach(i,arg;args)
		{
			ret[i] = toJavaString!false(env,arg);
		}
		return Tuple!JavaStringTup(ret);
	}
}

///
auto mapJavaString(Args...)(JavaEnvironment* env,Args args)
{
	alias JStringTup = Repeat!(args.length,jstring);
	jstring[args.length] ret;
	foreach(i,arg;args)
	{
		ret[i] = arg.str;
	}
	return Tuple!JStringTup(ret);
}

///
template ToString(args...)
{
	///
	alias StringTup = Repeat!(args.length,string);

	///
	auto create()
	{
		string[args.length] ret;
		foreach(i,arg;args)
		{
			ret[i] = arg.to!string;
		}
		return Tuple!StringTup(ret);
	}
}
