///
module kaleidic.api.carbon.jni.client;
import core.thread;
import core.time;

import std.algorithm;
import std.array:Appender,array;
import std.conv:to;
import std.datetime;
import std.exception:enforce;
import std.format;
import std.stdio;
import std.string;
import std.typecons:Tuple,tuple;
import asdf;
static import std.file;
import jni;

//import kaleidic.api.carbon.subscribe;
import kaleidic.api.carbon.jni.javautil;
version(LDC)
{
	import std.meta:Alias;
	import kaleidic.helper.ldcutil;
}
else
{
	import std.meta:Repeat,Alias;
}
import core.stdc.stdio:printf;

///
enum JNI_VERSION = JNI_VERSION_1_6;
///
void function(void delegate()) registerOnCompleted;
///
void function(void delegate(string)) registerOnNext;
///
void function(void delegate(string)) registerOnError;


///
void createJVM(string[] options)
{
	kaleidicJVM = KaleidicJVM.factory();
	kaleidicJVM.create(options);
}
///
enum CarbonClassPath = "/home/lisharc_sym/.m2/repository/carbon-example/carbon-example/1.0-SNAPSHOT/carbon-example-1.0-SNAPSHOT.jar";


///
shared static this()
{
    static import carbonlib=kaleidic.api.carbon.jni.subscribeshim.dynamiclib;
    import core.runtime: Runtime;
    import core.stdc.stdlib;
    import core.sys.posix.dlfcn:dlsym;
    auto handler = Runtime.loadLibrary("libsubscribeshim.so");
    registerOnCompleted = cast(typeof(registerOnCompleted))dlsym(handler,carbonlib.registerOnCompleted.mangleof.ptr);
    registerOnNext= cast(typeof(registerOnNext))dlsym(handler,carbonlib.registerOnNext.mangleof.ptr);
    registerOnError= cast(typeof(registerOnError)) dlsym(handler,carbonlib.registerOnError.mangleof.ptr);
}

///
struct CarbonJavaClient
{
	@disable this();
	@disable this(this);
	JavaEnvironment* env;
	jmethodID[string] methods;
	jmethodID kaleidicCarbonClientConstructor;
	jobject kaleidicCarbonClient;
	string[string] methodMap;
	jclass[] referencesToTidy;
	void*[string] subscriptionHandles;

	jclass kaleidicCarbonClientClass()
	{
		return findClassAtila(this.env.p,"symmetry/carbon/example/KaleidicCarbonClient");
		//return kaleidicJVM.classHandles["symmetry/carbon/example/KaleidicCarbonClient"];
	}

	void kaleidicCarbonClientClass(jclass arg)
	{
		if (arg is null)
			kaleidicJVM.classHandles.remove("symmetry/carbon/example/KaleidicCarbonClient");
		else
			kaleidicJVM.classHandles["symmetry/carbon/example/KaleidicCarbonClient"] = arg;
	}


	void dispose()
	{
		writefln("* CarbonJavaClient destructor running");
		if(kaleidicCarbonClientConstructor !is null)
		{
			env.deleteGlobalRef(kaleidicCarbonClientConstructor);
			kaleidicCarbonClientConstructor = null;
		}
		referencesToTidy.each!(reference => env.deleteGlobalRef(reference));
		if (kaleidicCarbonClient !is null)
		{
			env.deleteGlobalRef(kaleidicCarbonClient);
			kaleidicCarbonClient = null;
		}
		if (kaleidicCarbonClientClass !is null)
		{
			env.deleteGlobalRef(kaleidicCarbonClientClass);
			kaleidicCarbonClientClass = null;
		}
		auto e = env.checkJavaException;
		if (!e)
			writefln("* exception running dispose on CarbonJavaClient: %s",e.message);
		env.dispose();
		destroy(env);
		writefln("* CarbonJavaClient destructor complete");
	}

	private auto getEnv()
	{
		return *((*env).p);
	}

	private void initializeMethodKeys()
	{
		this.methodMap = [
			"getRaw":	"(Ljava/lang/String;)Ljava/lang/String;",
			//"carbonFactory": "(Ljava/lang/String;)Lsymmetry/carbon/client/ICarbonClient;",
			//"dispose": "(Lsymmetry/carbon/client/ICarbonClient;)V",
			"getStatic":	"(Ljava/lang/String;)Ljava/lang/String;",
			"getTimeSeries": "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
			"getSavedIdentifiers": "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
			"subscribeToMarketData": "([Ljava/lang/String;)Ljava/lang/AutoCloseable;",
			"closeMarketDataSubscription": "(Ljava/lang/AutoCloseable;)V",
		];
	}

	private string cleanCarbonEnvironment(string carbonEnvironment)
	{
		carbonEnvironment = carbonEnvironment.strip.toUpper;
		if (carbonEnvironment.length==0)
			carbonEnvironment = "PRD";
		return carbonEnvironment;
	}

	private jobject callKaleidicCarbonClientConstructor(string carbonEnvironment, string serviceUser, string serviceUserPassword, string trustStore, string trustStorePassword)
	{
		kaleidicCarbonClientConstructor= env.getConstructor(kaleidicCarbonClientClass, "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
		kaleidicCarbonClient = getEnv
					.NewObject(
						env.p,
						kaleidicCarbonClientClass,
						kaleidicCarbonClientConstructor,
						env.toJavaString!false(carbonEnvironment).str,
						env.toJavaString!false(serviceUser).str,
						env.toJavaString!false(serviceUserPassword).str,
						env.toJavaString!false(trustStore).str,
						env.toJavaString!false(trustStorePassword).str
						);
		enforce(kaleidicCarbonClient !is null, "unable to construct carbon client: returned null");
		auto e = env.checkJavaException;
		enforce(!e, "JVM call to create carbon instance: " ~e.message);
		return env.newGlobalRef(kaleidicCarbonClient);
	}

	private void mapMethods()
	{
		foreach(methodName;methodMap.keys)
		{
		    methods[methodName]= env.getMethodID(kaleidicCarbonClientClass, methodName, methodMap[methodName]);
		}
	}

	this(string carbonEnvironment, string serviceUser, string serviceUserPassword, string trustStore, string trustStorePassword, string carbonClassPath = CarbonClassPath)
	{
		initializeMethodKeys();
		carbonEnvironment = cleanCarbonEnvironment(carbonEnvironment);
		env = new JavaEnvironment("java.class.path=" ~ carbonClassPath);
		auto e = env.checkJavaException;
		enforce(!e, "JVM call to create carbon instance: " ~e.message);
		kaleidicCarbonClient = callKaleidicCarbonClientConstructor(carbonEnvironment,serviceUser,serviceUserPassword,trustStore,trustStorePassword);
		e = env.checkJavaException;
		enforce(!e, "JVM call to create carbon instance: " ~e.message);
		enforce (kaleidicCarbonClient !is null, "null carbon client constructor");
		writefln("* created carbon instance");
		kaleidicCarbonClient = env.newGlobalRef(kaleidicCarbonClient);
		enforce (kaleidicCarbonClient !is null, "null carbon client constructor reference");
		e = env.checkJavaException;
		enforce(!e, "JVM call to create carbon instance: " ~e.message);
		mapMethods();
		e = env.checkJavaException;
		enforce(!e, "JVM call to create carbon instance: " ~e.message);
		writefln("* mapped methods and successfully created carbon instance");
	}

	void checkValid()
	{
		enforce (env !is null, "JavaEnvironment is null");
		enforce (env.p !is null, "*JavaEnvironment is null");
		enforce (kaleidicCarbonClient !is null, "kaleidicCarbonClient is null");
		enforce (methods.keys.length == methodMap.keys.length, "not all methods are mapped");
	}


	T callCarbonClientMethod(T,string method)(void* arg)
	if (is(T==string) || is(T==Asdf))
	{
		auto methodID = methods[method];
		enforce (methodID !is null, "callCarbonClientMethod for " ~ method~ " called on null methodID");
		auto result = getEnv.CallObjectMethod(env.p,kaleidicCarbonClient,methodID,arg);
		auto e = checkJavaException(env);
		enforce(!e, "JVM call to " ~ method ~  " generated Java Exception " ~ e.message);
		enforce (result !is null, "callCarbonClientMethod for " ~ method ~ " CallObjectMethod returned null");
		static if (is(T==void*))
		{
			return result;
		}
		else
		{
			auto s = cast(string) env.fromJavaString(result);
			writeln("****");
			writeln(s);
			writeln("****");

			static if (is(T==Asdf))
			{
				std.file.write("carbon.json",s);
				auto ret = parseJson(s.skipGarbageStart);
				return ret;
			}
			else
			{
				std.file.write("carbon.json",s);
				return s;
			}
		}
	}

	T callCarbonClientMethod(T,string method,Args...)(Args args)
	if (is(T==string) || is(T==Asdf) && !(args.length==1 && is(args[0]==void*)))
	{
		auto methodID = methods[method];
		enforce (methodID !is null, "callCarbonClientMethod for " ~ method~ " called on null methodID");
		writefln("args =  %s", ToString!args.create());
		auto javaStrings = ToJavaString!args.create(env);
		auto result = getEnv.CallObjectMethod(env.p,kaleidicCarbonClient,methodID,mapJavaString(env,javaStrings.expand).expand);
		//foreach(ref javaString;javaStrings)
		//	javaString.dispose();
		//auto e = checkJavaException(env);
		//enforce(!e, "JVM call to " ~ method ~ " for arg: " ~ ToString!args.create().to!string ~ " generated Java Exception " ~ e.message);
		enforce (result !is null, "callCarbonClientMethod for " ~ method ~ " CallObjectMethod returned null");
		static if (is(T==void*))
		{
			result = env.newGlobalRef(result);
			referencesToTidy~=result;
			return result;
		}
		else
		{
			auto s = cast(string)env.fromJavaString(result);
			writefln("result = %s",s);
			std.file.write("carbon.json",s);
			static if (is(T==Asdf))
			{
				auto ret = parseJson(s.skipGarbageStart);
				return ret;
			}
			else
			{
				return s;
			}
		}
	}

	T callCarbonClientMethod(T,string method)(string[] args)
	if (is(T==string) || is(T==Asdf) || is(T==void*))
	{
		auto methodID = methods[method];
		enforce (methodID !is null, "callCarbonClientMethod for " ~ method~ " called on null methodID");
		auto javaArgs = env.toJava(args);
		scope(exit)
			javaArgs.dispose();
		auto result = getEnv.CallObjectMethod(env.p,kaleidicCarbonClient,methodID,javaArgs.arr);
		auto e = checkJavaException(env);
		enforce(!e, "JVM call to " ~ method ~ " for args: " ~ args.to!string ~ " generated Java Exception " ~ e.message);
		enforce (result !is null, "callCarbonClientMethod for " ~ method ~ " CallObjectMethod returned null");
		static if (is(T==void*))
		{
			result = env.newGlobalRef(result);
			referencesToTidy~=result;
			return result;
		}
		else
		{
			auto s = cast(string) env.fromJavaString(result);
			writefln("result = %s",s);
			static if (is(T==Asdf))
			{
				std.file.write("carbon.json",s);
				return parseJson(s.skipGarbageStart);
			}
			else
			{
				return s;
			}
		}
	}

	Asdf getDerived(string series = "symapp.derivedseries.config")
	{
		writefln("* check valid");
		checkValid();
		series=series.strip;
		writefln("* about to call on series: "~series);
		auto result = callCarbonClientMethod!(Asdf,"getRaw")(series);
		writeln("* got result");
		return result;
	}

	Asdf getStatic(string ticker)
	{
		checkValid();
		ticker = ticker.strip;
		return callCarbonClientMethod!(Asdf,"getStatic")(ticker);
	}

	Asdf getTimeSeries(string ticker, string type, DateTime startDate, DateTime endDate, string tenor = "")
	{
		checkValid();
		ticker = ticker.strip;
		type = type.strip;
		return callCarbonClientMethod!(Asdf,"getTimeSeries")(ticker,type,startDate,endDate,tenor);
	}

	Asdf getSavedIdentifiers(string type, string match)
	{
		checkValid();
		type = type.strip;
		match = match.strip;
		return callCarbonClientMethod!(Asdf,"getSavedIdentifiers")(type,match);
	}

	Asdf subscribeToMarketData(string[] tickers)
	{
		import std.uuid;
		checkValid();
		tickers = tickers.map!(ticker=>ticker.strip).array;
		auto ptr = callCarbonClientMethod!(void*,"subscribeToMarketData")(tickers);
		auto uuid = randomUUID().toString();
		subscriptionHandles[uuid] = ptr;
		struct Result
		{
			string status;
			string handle;
		}
		Result result;
		result.status = "success";
		result.handle = uuid;
		return result.serializeToAsdf;
	}

	Asdf closeMarketDataSubscription(string handle)
	{
		struct Ret
		{
			string status;
			string message;
		}
		checkValid();
		Ret ret;
		auto ptr = (handle in subscriptionHandles);
		if (ptr !is null)
		{
			auto result = callCarbonClientMethod!(string,"closeMarketDataSubscription")(*ptr);
			subscriptionHandles.remove(handle);
			ret.status = "success";
			ret.message = result;
			return ret.serializeToAsdf;
		}
		ret.status = "failure";
		return ret.serializeToAsdf;
	}
		//if (jvm !is null)
		//	(*jvm).DestroyJavaVM(jvm);
}
