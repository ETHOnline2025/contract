import { BigNumber } from 'ethers';
import { pino } from 'pino';
import { safelyAccessEnvVar } from './env.js';
// Level and format here should correspond with the agent options as much as possible
// https://docs.hyperlane.xyz/docs/operate/config-reference#logfmt
// A custom enum definition because pino does not export an enum
// and because we use 'off' instead of 'silent' to match the agent options
export var LogLevel;
(function (LogLevel) {
    LogLevel["Trace"] = "trace";
    LogLevel["Debug"] = "debug";
    LogLevel["Info"] = "info";
    LogLevel["Warn"] = "warn";
    LogLevel["Error"] = "error";
    LogLevel["Off"] = "off";
})(LogLevel || (LogLevel = {}));
let logLevel = toPinoLevel(safelyAccessEnvVar('LOG_LEVEL', true)) || 'info';
function toPinoLevel(level) {
    if (level && pino.levels.values[level])
        return level;
    // For backwards compat and also to match agent level options
    else if (level === 'none' || level === 'off')
        return 'silent';
    else
        return undefined;
}
export function getLogLevel() {
    return logLevel;
}
export var LogFormat;
(function (LogFormat) {
    LogFormat["Pretty"] = "pretty";
    LogFormat["JSON"] = "json";
})(LogFormat || (LogFormat = {}));
let logFormat = LogFormat.JSON;
const envLogFormat = safelyAccessEnvVar('LOG_FORMAT', true);
if (envLogFormat && Object.values(LogFormat).includes(envLogFormat))
    logFormat = envLogFormat;
export function getLogFormat() {
    return logFormat;
}
// Note, for brevity and convenience, the rootLogger is exported directly
export let rootLogger = createHyperlanePinoLogger(logLevel, logFormat);
export function getRootLogger() {
    return rootLogger;
}
export function configureRootLogger(newLogFormat, newLogLevel) {
    logFormat = newLogFormat;
    logLevel = toPinoLevel(newLogLevel) || logLevel;
    rootLogger = createHyperlanePinoLogger(logLevel, logFormat);
    return rootLogger;
}
export function setRootLogger(logger) {
    rootLogger = logger;
    return rootLogger;
}
export function createHyperlanePinoLogger(logLevel, logFormat) {
    return pino({
        level: logLevel,
        name: 'hyperlane',
        formatters: {
            // Remove pino's default bindings of hostname but keep pid
            bindings: (defaultBindings) => ({ pid: defaultBindings.pid }),
        },
        hooks: {
            logMethod(inputArgs, method, level) {
                // Pino has no simple way of setting custom log shapes and they
                // recommend against using pino-pretty in production so when
                // pretty is enabled we circumvent pino and log directly to console
                if (logFormat === LogFormat.Pretty &&
                    level >= pino.levels.values[logLevel]) {
                    // eslint-disable-next-line no-console
                    console.log(...inputArgs);
                    // Then return null to prevent pino from logging
                    return null;
                }
                return method.apply(this, inputArgs);
            },
        },
    });
}
export function ethersBigNumberSerializer(key, value) {
    // Check if the value looks like a serialized BigNumber
    if (typeof value === 'object' &&
        value !== null &&
        value.type === 'BigNumber' &&
        value.hex) {
        return BigNumber.from(value.hex).toString();
    }
    return value;
}
//# sourceMappingURL=logging.js.map