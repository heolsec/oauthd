async = require 'async'
jf = require 'jsonfile'

module.exports = (env) ->
	env.debug 'Initializing plugins engine'
	pluginsEngine = {
		plugin: {}
	}
	env.plugins = pluginsEngine.plugin
	env.hooks = {
		'connect.auth': []
		'connect.callback': []
		'connect.backend': []
	}
	env.callhook = -> # (name, ..., callback)
		name = Array.prototype.slice.call(arguments)
		args = name.splice(1)
		name = name[0]
		callback = args.splice(-1)
		callback = callback[0]
		return callback() if not env.hooks[name]
		cmds = []
		args[args.length] = null
		for hook in env.hooks[name]
			do (hook) ->
				cmds.push (cb) ->
					args[args.length - 1] = cb
					hook.apply pluginsEngine.data, args
		async.series cmds, callback

	env.addhook = (name, fn) ->
		env.hooks[name] ?= []
		env.hooks[name].push fn

	pluginsEngine.load = (plugin_name) ->
		env.debug "Loading '" + plugin_name + "'."
		try 
			plugin_data = require(process.cwd() + '/plugins/' + plugin_name + '/plugin.json')
		catch
			env.debug 'Absent plugin.json for plugin \'' + plugin_name + '\'.'
			plugin_data = {}
		if plugin_data.main?
			entry_point = '/' + plugin_data.main
		else
			entry_point = '/index'
		try
			plugin = require(process.cwd() + '/plugins/' + plugin_name + entry_point)(env)
			env.config.plugins.push plugin_name
			pluginsEngine.plugin[plugin_name] = plugin
		catch 
			env.debug "Error requiring plugin \'" + plugin_name + "\' entry point."
		return

	pluginsEngine.init = (callback) ->
		try
			jf.readFile process.cwd() + '/plugins.json', (err, obj) ->
				throw err if err
				if not obj?
					obj = {}
				for pluginname, pluginversion of obj
					pluginsEngine.load pluginname
				return callback true
		catch err
			env.debug 'An error occured: ' + e.message
			throw err if err
			return callback true

	pluginsEngine.list = (callback) ->
		list = []
		jf.readFile process.cwd() + '/plugins.json', (err, obj) ->
			return callback err if err
			if obj?
				for key, value of obj
					list.push key
			return callback null, list

	pluginsEngine.run = (name, args, callback) ->
		if typeof args == 'function'	
			callback = args
			args = []
		args.push null
		calls = []
		for k,plugin of pluginsEngine.plugin
			if typeof plugin[name] == 'function'
				do (plugin) ->
					calls.push (cb) ->
						args[args.length-1] = cb
						plugin[name].apply env, args
		async.series calls, ->
			args.pop()
			callback.apply null,arguments
			return
		return

	pluginsEngine.runSync = (name, args) ->
		for k,plugin of pluginsEngine.plugin
			if typeof plugin[name] == 'function'
				plugin[name].apply env, args
		return

	pluginsEngine